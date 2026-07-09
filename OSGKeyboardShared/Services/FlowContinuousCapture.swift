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
    // `AVAudioConverter` / `AVAudioFormat` are not `Sendable`, so the state and
    // the returned converter are guarded manually via the unchecked lock APIs.
    private let lock = OSAllocatedUnfairLock<(converter: AVAudioConverter, source: AVAudioFormat)?>(uncheckedState: nil)
    let targetFormat: AVAudioFormat

    init(targetFormat: AVAudioFormat) {
        self.targetFormat = targetFormat
    }

    /// Returns a converter valid for `sourceFormat`, rebuilding it lazily when
    /// the hardware route (and thus the buffer format) changes.
    func converter(for sourceFormat: AVAudioFormat) -> AVAudioConverter? {
        lock.withLockUnchecked { state in
            if let state, state.source == sourceFormat {
                return state.converter
            }
            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                state = nil
                return nil
            }
            state = (converter, sourceFormat)
            return converter
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

    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.osgkeyboard.shared", category: "FlowCapture")

    public init() {}

    public var running: Bool { isRunning }

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

    /// Configure `.playAndRecord`, install a permanent input tap, start the engine.
    public func start() throws {
        guard !isRunning else { return }
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
            try? await Task.sleep(nanoseconds: 50_000_000)
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
            notifyEngineLiveChanged()
        case .ended:
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

            // Derive the converter from the *live* buffer format so a mid-session
            // route change (e.g. 48 kHz → 24 kHz) is handled transparently.
            let sourceFormat = buffer.format
            let targetFormat = downsampler.targetFormat
            guard sourceFormat.sampleRate > 0,
                  let converter = downsampler.converter(for: sourceFormat) else { return }

            let outFrames = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / sourceFormat.sampleRate
            )
            guard outFrames > 0,
                  let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames)
            else { return }

            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            guard status == .haveData, error == nil, outBuffer.frameLength > 0 else { return }

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
