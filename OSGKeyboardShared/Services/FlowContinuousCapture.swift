// FlowContinuousCapture.swift
// OSGKeyboard · Shared
//
// TypeWhisper-style continuous mic capture for Flow sessions: one
// AVAudioEngine + input tap for the entire session. Utterances gate
// whether buffers are forwarded to ASR; levels are always computed on
// the audio thread and read from the main thread (never UserDefaults
// from the realtime tap — that caused cross-process crashes).

import Foundation
import AVFoundation
import os

private enum FlowCaptureConstants {
    static let levelBarCount = 24
    static let targetSampleRate: Double = 16_000
    static let drainPollIntervalNs: UInt64 = 20_000_000
}

private enum UtteranceGatePhase: Equatable {
    case idle
    case recording
    case draining
}

/// Thread-safe relay for utterance-scoped ASR snapshots.
private final class FlowCaptureStreamRelay: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var continuation: AsyncStream<AudioBufferSnapshot>.Continuation?

    func bind(_ continuation: AsyncStream<AudioBufferSnapshot>.Continuation) {
        lock.withLock { self.continuation = continuation }
    }

    func replay(_ snapshots: [AudioBufferSnapshot]) {
        lock.withLock {
            for snapshot in snapshots {
                continuation?.yield(snapshot)
            }
        }
    }

    func yield(_ snapshot: AudioBufferSnapshot) {
        _ = lock.withLock { continuation?.yield(snapshot) }
    }

    func finish() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
        }
    }
}

/// Rolling pre-roll while utterance gate is closed (~400 ms at typical tap rates).
private final class FlowPrerollStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var snapshots: [AudioBufferSnapshot] = []
    private let maxCount: Int

    init(maxCount: Int = 6) {
        self.maxCount = maxCount
    }

    func append(_ snapshot: AudioBufferSnapshot) {
        lock.withLock {
            snapshots.append(snapshot)
            if snapshots.count > maxCount {
                snapshots.removeFirst(snapshots.count - maxCount)
            }
        }
    }

    func drain() -> [AudioBufferSnapshot] {
        lock.withLock {
            let drained = snapshots
            snapshots.removeAll()
            return drained
        }
    }
}

/// Rolling bar levels updated from the audio tap; read on the main actor.
private final class FlowLevelStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var levels: [Float]

    init(barCount: Int) {
        levels = Array(repeating: 0, count: barCount)
    }

    func update(from buffer: AVAudioPCMBuffer, barCount: Int) {
        let computed = Self.calculateLevels(from: buffer, barCount: barCount)
        lock.withLock { levels = computed }
    }

    func snapshot() -> [Float] {
        lock.withLock { levels }
    }

    private static func calculateLevels(from buffer: AVAudioPCMBuffer, barCount: Int) -> [Float] {
        guard let channelData = buffer.floatChannelData else {
            return Array(repeating: 0, count: barCount)
        }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return Array(repeating: 0, count: barCount)
        }
        let samplesPerBar = max(frameLength / barCount, 1)
        var result = [Float]()
        result.reserveCapacity(barCount)
        for barIndex in 0..<barCount {
            let start = barIndex * samplesPerBar
            let end = min(start + samplesPerBar, frameLength)
            var sum: Float = 0
            for i in start..<end {
                sum += abs(channelData[0][i])
            }
            let avg = sum / Float(max(end - start, 1))
            result.append(min(avg * 50, 1))
        }
        return result
    }
}

/// Last observed audio tap timestamp. This lets the host publish "ready"
/// only after the microphone pipeline has produced real frames.
private final class FlowAudioProofStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: TimeInterval(0))

    func markFrameReceived() {
        lock.withLock { $0 = Date().timeIntervalSince1970 }
    }

    func reset() {
        lock.withLock { $0 = 0 }
    }

    func hasRecentFrame(maxAge: TimeInterval) -> Bool {
        let timestamp = lock.withLock { $0 }
        guard timestamp > 0 else { return false }
        return Date().timeIntervalSince1970 - timestamp <= maxAge
    }
}

/// Route-adaptive downsampling converter, safe to call from the realtime tap.
///
/// `AVAudioEngine.installTap(format:)` traps with an **uncatchable** NSException
/// when the format passed to it does not match the input node's *live* format.
/// After an audio-route change — which the on-device `SpeechAnalyzer` triggers
/// during warmup by reconfiguring the shared `AVAudioSession` — the value
/// returned by `inputNode.outputFormat(forBus:)` can lag behind the real
/// hardware rate (e.g. it reports 48 kHz while the node has already switched to
/// 24 kHz). Installing a tap with that stale explicit format crashes the whole
/// app (`Failed to create tap due to format mismatch`).
///
/// We therefore install the tap with `format: nil` (which always uses the
/// node's live format) and rebuild the sample-rate converter *here* whenever the
/// incoming buffer's format actually changes, so downsampling to the ASR target
/// rate is always valid regardless of route churn.
private final class AdaptiveDownsampler: @unchecked Sendable {
    // `AVAudioConverter` / `AVAudioFormat` / `AVAudioPCMBuffer` are not
    // `Sendable`, so the state is guarded manually via the unchecked lock
    // APIs. The scratch output buffer is REUSED across tap callbacks —
    // allocating on the realtime audio thread risks priority inversion, and
    // taps on one bus are serialized, so a single scratch is safe as long as
    // callers copy its contents out before returning (AudioBufferSnapshot
    // does exactly that).
    private struct State {
        var converter: AVAudioConverter
        var source: AVAudioFormat
        var scratch: AVAudioPCMBuffer
    }

    private let lock = OSAllocatedUnfairLock<State?>(uncheckedState: nil)
    let targetFormat: AVAudioFormat

    /// Frame headroom for the reusable output buffer. Taps deliver ≤4096
    /// input frames; output frames = input × (16k / hardwareRate), which
    /// exceeds input only for sub-16 kHz hardware (rare telephony routes),
    /// so 2× the tap size covers every realistic ratio.
    private static let scratchCapacity: AVAudioFrameCount = 8_192

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    /// Downsamples `buffer` into the reusable scratch buffer and returns it,
    /// rebuilding the converter lazily when the hardware route (and thus the
    /// source format) changes. The returned buffer is only valid until the
    /// next call — copy its samples out synchronously.
    func convertReusingScratch(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let sourceFormat = buffer.format
        guard sourceFormat.sampleRate > 0 else { return nil }
        return lock.withLockUnchecked { state -> AVAudioPCMBuffer? in
            if state == nil || state!.source != sourceFormat {
                guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
                      let scratch = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: Self.scratchCapacity
                      ) else {
                    state = nil
                    return nil
                }
                state = State(converter: converter, source: sourceFormat, scratch: scratch)
            }
            guard let current = state else { return nil }

            let wanted = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate
            )
            guard wanted > 0, wanted <= current.scratch.frameCapacity else { return nil }
            current.scratch.frameLength = 0

            // ONE-SHOT input: the converter keeps pulling until the output
            // buffer's frameCapacity is full, and the scratch is deliberately
            // oversized — feeding the same tap buffer on every pull would
            // duplicate the audio ~6× (stuttering ASR input). After the
            // single feed we report "ran dry", so the expected status is
            // `.inputRanDry` (output not full), not `.haveData`.
            var provided = false
            var error: NSError?
            let status = current.converter.convert(to: current.scratch, error: &error) { _, outStatus in
                if provided {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                provided = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil, current.scratch.frameLength > 0 else { return nil }
            return current.scratch
        }
    }
}

@MainActor
public final class FlowContinuousCapture {

    public enum StartError: LocalizedError {
        case invalidHardwareFormat(sampleRate: Double, channels: Int)
        case formatCreateFailed
        case converterCreateFailed
        case engineStartFailed(String)
        case audioSessionFailed(String)

        public var errorDescription: String? {
            switch self {
            case .invalidHardwareFormat(let sr, let ch):
                return String.localizedStringWithFormat(
                    NSLocalizedString("preview.error.micUnavailable", comment: ""),
                    sr,
                    ch
                )
            case .formatCreateFailed:
                return NSLocalizedString("preview.error.formatCreate", comment: "")
            case .converterCreateFailed:
                return NSLocalizedString("preview.error.converterCreate", comment: "")
            case .engineStartFailed(let detail):
                return String.localizedStringWithFormat(
                    NSLocalizedString("preview.error.engineStart", comment: ""),
                    detail
                )
            case .audioSessionFailed(let detail):
                return String.localizedStringWithFormat(
                    NSLocalizedString("preview.error.audioSession", comment: ""),
                    detail
                )
            }
        }
    }

    public static let levelBarCount = FlowCaptureConstants.levelBarCount

    private let audioEngine = AVAudioEngine()
    private let streamRelay = FlowCaptureStreamRelay()
    private let prerollStore = FlowPrerollStore()
    private let levelStore = FlowLevelStore(barCount: FlowCaptureConstants.levelBarCount)
    private let audioProofStore = FlowAudioProofStore()
    private let gate = OSAllocatedUnfairLock(initialState: UtteranceGatePhase.idle)
    private let drainTracker = FlowCaptureDrainTracker()
    private let tailSampleCounter = OSAllocatedUnfairLock(initialState: 0)

    private var downsampler: AdaptiveDownsampler?
    private var targetFormat: AVAudioFormat?
    private var hwFormat: AVAudioFormat?
    private var drainPolicy = FlowCaptureTailDrainPolicy.flowDefault

    private var didInstallTap = false
    private var isRunning = false
    private var isRebuilding = false
    private var interrupted = false
    /// When the engine last (re)activated — a freshly started engine has
    /// produced no frames yet and must not be misclassified as a zombie.
    private var lastActivationAt = Date.distantPast

    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.osgkeyboard.shared", category: "FlowCapture")

    public init() {}

    public var running: Bool { isRunning }

    /// True between interruption `.began` and `.ended` (phone call, Siri).
    /// While set, `setActive(true)` is guaranteed to fail — owners should
    /// wait for `.ended` (which rebuilds the engine) instead of retrying.
    public var isInterrupted: Bool { interrupted }

    /// True when the capture session flag, tap, and audio engine are all live.
    public var engineIsLive: Bool {
        isRunning && didInstallTap && audioEngine.isRunning
    }

    /// True only when the engine is live and the input tap has recently
    /// delivered an actual audio frame.
    public func engineHasRecentAudio(maxAge: TimeInterval = 1) -> Bool {
        engineIsLive && audioProofStore.hasRecentFrame(maxAge: maxAge)
    }

    /// Called on the main actor when `engineIsLive` may have changed.
    public var onEngineLiveChanged: ((Bool) -> Void)?

    /// Called on the main actor when the system interrupted capture (phone
    /// call, Siri). The session owner should fail any mic-open utterance —
    /// audio frames stop arriving, so continuing to "record" only captures
    /// a silence gap the user cannot see.
    public var onInterruptionBegan: (() -> Void)?

    /// Configure `.playAndRecord`, install a permanent input tap, start the engine.
    ///
    /// Idempotent: "already running and healthy" is a warm-start fast path,
    /// while "already running but producing no audio" is a zombie state
    /// (force-quit relaunch, failed cold start, mediaserverd reset) that is
    /// torn down and rebuilt in place. It must never be a silent no-op —
    /// a `guard !isRunning` early-return here turned every cold-start retry
    /// into a guaranteed audio-proof timeout.
    public func start() throws {
        if isRunning {
            let startedMomentsAgo = Date().timeIntervalSince(lastActivationAt) < 2
            if engineIsLive && (engineHasRecentAudio(maxAge: 2) || startedMomentsAgo) {
                // Healthy warm engine — or one so fresh it simply hasn't
                // produced its first frame yet (interleaved start attempts
                // land here; rebuilding a 100 ms-old engine only multiplies
                // audio-session churn in the fragile post-relaunch window).
                return
            }
            log.info("start(): zombie engine detected (running but no live audio) — forcing rebuild")
            stop()
        }
        audioProofStore.reset()
        try activateEngine()
        isRunning = true
        installSessionObservers()
        notifyEngineLiveChanged()
    }

    /// Bring up the audio session + engine for the *current* hardware route.
    /// Reused for route-change / interruption recovery, so it always rebuilds
    /// the tap against the live hardware format (which changes when the user
    /// plugs in AirPods or a wired headset mid-session).
    private func activateEngine() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw StartError.audioSessionFailed(error.localizedDescription)
        }

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw StartError.invalidHardwareFormat(
                sampleRate: hardwareFormat.sampleRate,
                channels: Int(hardwareFormat.channelCount)
            )
        }

        guard let resolvedTargetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: FlowCaptureConstants.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw StartError.formatCreateFailed
        }

        // Route-adaptive converter: it rebuilds itself from the live buffer
        // format inside the tap, so it never assumes a fixed hardware rate.
        let downsampler = AdaptiveDownsampler(targetFormat: resolvedTargetFormat)
        self.downsampler = downsampler
        targetFormat = resolvedTargetFormat
        hwFormat = hardwareFormat

        // Rebuild the tap so its bound hardware format matches the new route.
        if didInstallTap {
            inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }

        let gateLock = gate
        let relay = streamRelay
        let preroll = prerollStore
        let levels = levelStore
        let proof = audioProofStore
        let tracker = drainTracker
        let tailCounter = tailSampleCounter
        let policy = drainPolicy
        let tap = Self.makeAudioTapBlock(
            downsampler: downsampler,
            gate: gateLock,
            levelStore: levels,
            audioProofStore: proof,
            prerollStore: preroll,
            streamRelay: relay,
            drainTracker: tracker,
            tailSampleCounter: tailCounter,
            drainPolicy: policy
        )
        // `format: nil` binds the tap to the input node's *live* format. Passing
        // an explicit (possibly stale) format here is what crashed the app on a
        // route change (48 kHz client vs 24 kHz hardware); nil can never mismatch.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil, block: tap)
        didInstallTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw StartError.engineStartFailed(error.localizedDescription)
        }
        lastActivationAt = Date()
    }

    /// Tear down the engine and release the audio session.
    public func stop() {
        removeSessionObservers()
        gate.withLock { $0 = .idle }
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        streamRelay.finish()

        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isRunning = false
        interrupted = false
        audioProofStore.reset()
        downsampler = nil
        targetFormat = nil
        hwFormat = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        notifyEngineLiveChanged()
    }

    /// Re-activate capture after returning from background without
    /// reinstalling the tap (iOS may deactivate the audio session).
    ///
    /// Doubles as the interruption-recovery probe: `setActive(true)` FAILS
    /// while a call/Siri interruption is live and succeeds once it ends, so a
    /// successful reassert proves the interruption is over. iOS does not
    /// guarantee delivery of `.ended` (commonly dropped when the app was
    /// suspended during the call), so this is the only reliable way to clear
    /// the `interrupted` latch in that case.
    @discardableResult
    public func reassertIfRunning() -> Bool {
        guard isRunning else { return false }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            interrupted = false
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            notifyEngineLiveChanged()
            return engineIsLive
        } catch {
            notifyEngineLiveChanged()
            return false
        }
    }

    public func awaitAudioFlowing(
        timeout: TimeInterval,
        recentFrameMaxAge: TimeInterval = 1
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if engineHasRecentAudio(maxAge: recentFrameMaxAge) {
                return true
            }
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                // Cancelled — bail out instead of busy-spinning the main
                // actor for the rest of the window (a cancelled Task.sleep
                // returns immediately, starving concurrent start attempts).
                return false
            }
        }
        return engineHasRecentAudio(maxAge: recentFrameMaxAge)
    }

    // MARK: - Route / interruption recovery

    private func installSessionObservers() {
        let center = NotificationCenter.default
        if routeObserver == nil {
            routeObserver = center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let reasonRaw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                MainActor.assumeIsolated { self?.handleRouteChange(reasonRaw: reasonRaw) }
            }
        }
        if interruptionObserver == nil {
            interruptionObserver = center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let typeRaw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                MainActor.assumeIsolated {
                    self?.handleInterruption(typeRaw: typeRaw, optionsRaw: optionsRaw)
                }
            }
        }
        // Apple QA1749: when the system media server resets, the engine,
        // converter and audio session all become orphaned and must be
        // rebuilt from scratch — otherwise capture silently produces no
        // audio (another cause of "waveform moves but ASR is empty").
        if mediaResetObserver == nil {
            mediaResetObserver = center.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleMediaServicesReset() }
            }
        }
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        if let routeObserver { center.removeObserver(routeObserver) }
        if let interruptionObserver { center.removeObserver(interruptionObserver) }
        if let mediaResetObserver { center.removeObserver(mediaResetObserver) }
        routeObserver = nil
        interruptionObserver = nil
        mediaResetObserver = nil
    }

    private func handleMediaServicesReset() {
        guard isRunning else { return }
        log.info("Media services were reset — rebuilding engine and converter")
        rebuildEngine()
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard isRunning else { return }
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            log.info("Audio route changed (\(reasonRaw, privacy: .public)) — rebuilding engine")
            rebuildEngine()
        default:
            break
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            log.info("Audio interruption began")
            interrupted = true
            notifyEngineLiveChanged()
            onInterruptionBegan?()
        case .ended:
            interrupted = false
            guard isRunning else { return }
            let shouldResume: Bool
            if let optionsRaw {
                shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            } else {
                shouldResume = true
            }
            if shouldResume {
                log.info("Audio interruption ended — resuming capture")
                rebuildEngine()
            }
        @unknown default:
            break
        }
    }

    /// Stop and rebuild the engine against the current route, keeping
    /// `isRunning` intact so the session survives the swap transparently.
    private func rebuildEngine() {
        guard isRunning, !isRebuilding else { return }
        isRebuilding = true
        defer { isRebuilding = false }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        do {
            try activateEngine()
            notifyEngineLiveChanged()
        } catch {
            log.error("Engine rebuild failed: \(error.localizedDescription, privacy: .public)")
            notifyEngineLiveChanged()
        }
    }

    private func notifyEngineLiveChanged() {
        onEngineLiveChanged?(engineIsLive)
    }

    /// Begin forwarding downsampled buffers to ASR for one utterance.
    public func beginUtterance() -> AsyncStream<AudioBufferSnapshot> {
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        // Bind the consumer before opening the gate so early tap frames
        // are not dropped on the floor.
        streamRelay.bind(continuation)
        streamRelay.replay(prerollStore.drain())
        gate.withLock { $0 = .recording }
        return stream
    }

    /// Drain trailing PCM after the user stops, then finish the ASR stream.
    public func endUtteranceAndDrain(
        policy: FlowCaptureTailDrainPolicy = .flowDefault
    ) async -> FlowCaptureDrainReport {
        let currentPhase = gate.withLock { $0 }
        guard currentPhase == .recording else {
            return .skipped
        }

        drainPolicy = policy
        gate.withLock { $0 = .draining }
        drainTracker.beginDrain()

        var endedBySilence = false
        while true {
            let decision = drainTracker.shouldFinish(policy: policy)
            if decision.finished {
                endedBySilence = decision.endedBySilence
                break
            }
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: FlowCaptureConstants.drainPollIntervalNs)
        }

        // NOTE: We intentionally do NOT signal `.endOfStream` to the shared
        // downsampling converter here. `AVAudioConverter` is stateful: once its
        // input block returns `.endOfStream`, the converter is permanently
        // finished and every subsequent `.haveData` conversion (from the live
        // tap) returns no data — which silently starved every utterance after
        // the first (Apple docs + AVAudioConverter reuse guidance). Trailing
        // speech is already preserved by the live `.draining` forwarding loop
        // above; the converter's sub-millisecond internal filter tail is not
        // worth poisoning a session-long converter for.
        streamRelay.finish()
        gate.withLock { $0 = .idle }

        let tailSamples = tailSampleCounter.withLock { $0 }
        let report = FlowCaptureDrainReport(
            drainDurationSeconds: drainTracker.elapsedSeconds(),
            endedBySilence: endedBySilence,
            tailSampleCount: tailSamples
        )
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        FlowPipelineDiagnostics.logDrain(report)
        return report
    }

    /// Immediate stop without tail drain (abort / session teardown).
    public func cancelUtterance() {
        gate.withLock { $0 = .idle }
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        streamRelay.finish()
    }

    public func currentAudioLevels() -> [Float] {
        levelStore.snapshot()
    }

    // MARK: - Audio tap (nonisolated — runs on realtime thread)

    private nonisolated static func makeAudioTapBlock(
        downsampler: AdaptiveDownsampler,
        gate: OSAllocatedUnfairLock<UtteranceGatePhase>,
        levelStore: FlowLevelStore,
        audioProofStore: FlowAudioProofStore,
        prerollStore: FlowPrerollStore,
        streamRelay: FlowCaptureStreamRelay,
        drainTracker: FlowCaptureDrainTracker,
        tailSampleCounter: OSAllocatedUnfairLock<Int>,
        drainPolicy: FlowCaptureTailDrainPolicy
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            audioProofStore.markFrameReceived()
            levelStore.update(from: buffer, barCount: FlowCaptureConstants.levelBarCount)

            // The downsampler derives its converter from the *live* buffer
            // format (mid-session route changes handled transparently) and
            // returns a REUSED scratch buffer — no per-callback allocation
            // on the realtime thread. The snapshot below copies the samples
            // out before the next tap callback can overwrite the scratch.
            guard let outBuffer = downsampler.convertReusingScratch(buffer) else { return }

            let snapshot = AudioBufferSnapshot(buffer: outBuffer)
            guard !snapshot.samples.isEmpty else { return }

            let phase = gate.withLock { $0 }
            switch phase {
            case .recording, .draining:
                streamRelay.yield(snapshot)
                if phase == .draining {
                    drainTracker.noteAudio(samples: snapshot.samples, policy: drainPolicy)
                    tailSampleCounter.withLock { $0 += snapshot.samples.count }
                }
            case .idle:
                prerollStore.append(snapshot)
            }
        }
    }
}
