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
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

private enum FlowCaptureConstants {
    static let levelBarCount = 24
    static let targetSampleRate: Double = 16_000
    static let drainPollIntervalNs: UInt64 = 20_000_000
}

private enum UtteranceGatePhase: Equatable {
    case idle
    case recording
    case draining

    var label: String {
        switch self {
        case .idle: return "idle"
        case .recording: return "recording"
        case .draining: return "draining"
        }
    }
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

/// Rolling pre-roll while utterance gate is closed.
///
/// Sized by sample count (~3 s @ 16 kHz) so PiP mic spin-up between
/// `capture.start()` and `beginUtterance` does not discard the user's
/// opening words (the old 6-buffer cap was only ~400 ms).
private final class FlowPrerollStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var snapshots: [AudioBufferSnapshot] = []
    private let maxSamples: Int

    init(maxSamples: Int = 48_000) {
        self.maxSamples = maxSamples
    }

    func append(_ snapshot: AudioBufferSnapshot) {
        lock.withLock {
            snapshots.append(snapshot)
            var total = snapshots.reduce(0) { $0 + $1.samples.count }
            while total > maxSamples, !snapshots.isEmpty {
                let removed = snapshots.removeFirst()
                total -= removed.samples.count
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

/// Why a tap buffer never reached the recogniser.
///
/// Recorded as a plain integer on the realtime audio thread and rendered on the
/// main actor — calling `Logger` inside the tap would allocate and risk
/// priority inversion. Each of these was previously a bare `return`, which is
/// what made "waveform moves but the transcript is empty" invisible: levels and
/// the audio-proof timestamp are taken from the *raw* buffer, before
/// conversion, so they keep looking healthy while ASR receives nothing.
public enum FlowDownsampleFailure: Int, Sendable {
    case none = 0
    case invalidSourceFormat
    case converterCreateFailed
    case scratchOverflow
    case converterError
    case emptyOutput

    public var label: String {
        switch self {
        case .none: return "none"
        case .invalidSourceFormat: return "invalidSourceFormat"
        case .converterCreateFailed: return "converterCreateFailed"
        case .scratchOverflow: return "scratchOverflow"
        case .converterError: return "converterError"
        case .emptyOutput: return "emptyOutput"
        }
    }
}

/// Tap accounting for one utterance (`beginUtterance()` resets it).
public struct FlowCaptureFrameReport: Sendable, Equatable {
    public var framesReceived = 0
    public var framesConverted = 0
    public var framesDropped = 0
    public var samplesToASR = 0
    public var samplesToPreroll = 0
    public var lastFailure = FlowDownsampleFailure.none
    public var lastFailureSourceRate = 0
    public var lastFailureInputFrames = 0
    public var lastFailureWantedFrames = 0

    public init() {}

    /// The mic delivered frames but none survived conversion — i.e. the user
    /// saw a live waveform while the recogniser was fed silence.
    public var isFeedStarved: Bool {
        framesReceived > 0 && samplesToASR == 0
    }

    public var summary: String {
        var text = "frames=\(framesReceived) converted=\(framesConverted) "
            + "dropped=\(framesDropped) asrSamples=\(samplesToASR) "
            + "asrSeconds=\(FlowTrace.seconds(samples: samplesToASR)) "
            + "prerollSamples=\(samplesToPreroll)"
        if lastFailure != .none {
            text += " lastFailure=\(lastFailure.label)"
                + " failSourceRate=\(lastFailureSourceRate)"
                + " failInFrames=\(lastFailureInputFrames)"
                + " failWantFrames=\(lastFailureWantedFrames)"
        }
        return text
    }
}

/// Realtime-safe counters behind an unfair lock (same discipline as the gate).
private final class FlowCaptureFrameStats: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: FlowCaptureFrameReport())

    func noteFrameReceived() {
        lock.withLock { $0.framesReceived += 1 }
    }

    func noteConverted(samples: Int, reachedASR: Bool) {
        lock.withLock {
            $0.framesConverted += 1
            if reachedASR {
                $0.samplesToASR += samples
            } else {
                $0.samplesToPreroll += samples
            }
        }
    }

    func noteDropped(
        failure: FlowDownsampleFailure,
        sourceRate: Double,
        inputFrames: Int,
        wantedFrames: Int
    ) {
        lock.withLock {
            $0.framesDropped += 1
            $0.lastFailure = failure
            $0.lastFailureSourceRate = Int(sourceRate)
            $0.lastFailureInputFrames = inputFrames
            $0.lastFailureWantedFrames = wantedFrames
        }
    }

    func reset() {
        lock.withLock { $0 = FlowCaptureFrameReport() }
    }

    func snapshot() -> FlowCaptureFrameReport {
        lock.withLock { $0 }
    }
}

/// Outcome of one realtime conversion attempt. Carries the reason (and the
/// formats involved) so the drop can be explained after the fact.
private enum FlowDownsampleOutcome {
    case converted(AVAudioPCMBuffer)
    case failed(
        failure: FlowDownsampleFailure,
        sourceRate: Double,
        inputFrames: Int,
        wantedFrames: Int
    )
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
    func convertReusingScratch(_ buffer: AVAudioPCMBuffer) -> FlowDownsampleOutcome {
        let sourceFormat = buffer.format
        let sourceRate = sourceFormat.sampleRate
        let inputFrames = Int(buffer.frameLength)
        guard sourceRate > 0 else {
            return .failed(
                failure: .invalidSourceFormat,
                sourceRate: sourceRate,
                inputFrames: inputFrames,
                wantedFrames: 0
            )
        }
        return lock.withLockUnchecked { state -> FlowDownsampleOutcome in
            if state == nil || state!.source != sourceFormat {
                guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat),
                      let scratch = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: Self.scratchCapacity
                      ) else {
                    state = nil
                    return .failed(
                        failure: .converterCreateFailed,
                        sourceRate: sourceRate,
                        inputFrames: inputFrames,
                        wantedFrames: 0
                    )
                }
                state = State(converter: converter, source: sourceFormat, scratch: scratch)
            }
            guard let current = state else {
                return .failed(
                    failure: .converterCreateFailed,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: 0
                )
            }

            let wanted = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / sourceRate
            )
            guard wanted > 0, wanted <= current.scratch.frameCapacity else {
                return .failed(
                    failure: .scratchOverflow,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: Int(wanted)
                )
            }
            current.scratch.frameLength = 0

            // ONE-SHOT input: the converter keeps pulling until the output
            // buffer's frameCapacity is full, and the scratch is deliberately
            // oversized — feeding the same tap buffer on every pull would
            // duplicate the audio ~6× (stuttering ASR input). After the
            // single feed we report "ran dry", so the expected status is
            // `.inputRanDry` (output not full), not `.haveData`.
            let provided = OSAllocatedUnfairLock(initialState: false)
            var error: NSError?
            let status = current.converter.convert(to: current.scratch, error: &error) { _, outStatus in
                if provided.withLock({ $0 }) {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                provided.withLock { $0 = true }
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, error == nil else {
                return .failed(
                    failure: .converterError,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: Int(wanted)
                )
            }
            guard current.scratch.frameLength > 0 else {
                return .failed(
                    failure: .emptyOutput,
                    sourceRate: sourceRate,
                    inputFrames: inputFrames,
                    wantedFrames: Int(wanted)
                )
            }
            return .converted(current.scratch)
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

    /// Recreated after every hardware format transition. Reusing the same
    /// engine preserves a stale input node on some Bluetooth HFP changes.
    private var audioEngine = AVAudioEngine()
    private let streamRelay = FlowCaptureStreamRelay()
    private let prerollStore = FlowPrerollStore()
    private let levelStore = FlowLevelStore(barCount: FlowCaptureConstants.levelBarCount)
    private let audioProofStore = FlowAudioProofStore()
    private let gate = OSAllocatedUnfairLock(initialState: UtteranceGatePhase.idle)
    private let drainTracker = FlowCaptureDrainTracker()
    private let tailSampleCounter = OSAllocatedUnfairLock(initialState: 0)
    private let utterancePCMStore = FlowUtterancePCMStore(
        maxSampleCount: Int(FlowSessionKeys.maxUtteranceDuration) * 16_000
    )
    private let frameStats = FlowCaptureFrameStats()

    private var downsampler: AdaptiveDownsampler?
    private var targetFormat: AVAudioFormat?
    private var hwFormat: AVAudioFormat?
    private var activeRouteSnapshot: FlowAudioSessionSnapshot?
    private var drainPolicy = FlowCaptureTailDrainPolicy.flowDefault

    private var didInstallTap = false
    private var isRunning = false
    private var isRebuilding = false
    private var isActivatingEngine = false
    private var interrupted = false
    /// When the engine last (re)activated — a freshly started engine has
    /// produced no frames yet and must not be misclassified as a zombie.
    private var lastActivationAt = Date.distantPast

    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private var engineConfigurationObserver: NSObjectProtocol?
    private var routeRecoveryTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.osgkeyboard.shared", category: "FlowCapture")

    public init() {}

    public var running: Bool { isRunning }
    public private(set) var engineActivationCount = 0
    public private(set) var routeRecoveryCount = 0

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
    ///
    /// NOTE: this is a *raw* mic signal (taken before downsampling), so it
    /// proves the microphone works — not that the recogniser is being fed.
    /// Use `frameReport()` for the latter.
    public func engineHasRecentAudio(maxAge: TimeInterval = 1) -> Bool {
        engineIsLive && audioProofStore.hasRecentFrame(maxAge: maxAge)
    }

    /// Tap accounting since the last `beginUtterance()`, i.e. how much audio
    /// actually survived conversion and reached the recogniser.
    public func frameReport() -> FlowCaptureFrameReport {
        frameStats.snapshot()
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
    public func start() async throws {
        if isRunning {
            let startedMomentsAgo = Date().timeIntervalSince(lastActivationAt) < 2
            if engineIsLive && (engineHasRecentAudio(maxAge: 2) || startedMomentsAgo) {
                // Healthy warm engine — or one so fresh it simply hasn't
                // produced its first frame yet (interleaved start attempts
                // land here; rebuilding a 100 ms-old engine only multiplies
                // audio-session churn in the fragile post-relaunch window).
                FlowTrace.capture(
                    "start.warmReuse",
                    "engineLive=1 freshMs=\(Int(Date().timeIntervalSince(lastActivationAt) * 1000)) "
                        + frameStats.snapshot().summary
                )
                return
            }
            log.info("start(): zombie engine detected (running but no live audio) — forcing rebuild")
            FlowTrace.warn(
                "capture.start.zombieRebuild",
                "engineLive=\(engineIsLive ? 1 : 0) recentAudio=0 \(frameStats.snapshot().summary)"
            )
            stop()
        }
        audioProofStore.reset()
        FlowTrace.capture("start.begin", "coldEngine=1")
        installSessionObservers()
        do {
            try await activateEngine()
        } catch {
            removeSessionObservers()
            FlowTrace.warn("capture.start.failed", "error=\(error.localizedDescription)")
            throw error
        }
        isRunning = true
        notifyEngineLiveChanged()
        FlowTrace.capture("start.done", "engineLive=\(engineIsLive ? 1 : 0)")
    }

    /// Bring up the audio session + engine for the *current* hardware route.
    /// Reused for route-change / interruption recovery, so it always rebuilds
    /// the tap against the live hardware format (which changes when the user
    /// plugs in AirPods or a wired headset mid-session).
    private func activateEngine() async throws {
        isActivatingEngine = true
        defer { isActivatingEngine = false }
        let sessionSnapshot: FlowAudioSessionSnapshot
        do {
            sessionSnapshot = try await FlowAudioSessionCoordinator.shared.activateCapture()
        } catch {
            FlowTrace.warn(
                "capture.audioSession.activateFailed",
                "error=\(error.localizedDescription)"
            )
            throw StartError.audioSessionFailed(error.localizedDescription)
        }

        // AVAudioSession activation may replace the RemoteIO format. Build a
        // fresh engine only after activation so its input node cannot retain
        // the prior built-in-mic (48 kHz) format when HFP is now 24 kHz.
        // Retire the previous graph before publishing the fresh engine.
        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        await FlowAudioSessionCoordinator.shared.stopEngine(
            FlowAudioEngineHandle(audioEngine)
        )

        var candidateEngine = AVAudioEngine()
        var inputNode = candidateEngine.inputNode
        var hardwareFormat = inputNode.inputFormat(forBus: 0)
        var outputFormat = inputNode.outputFormat(forBus: 0)
        for _ in 0..<3 where abs(hardwareFormat.sampleRate - sessionSnapshot.sampleRate) >= 1 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            candidateEngine = AVAudioEngine()
            inputNode = candidateEngine.inputNode
            hardwareFormat = inputNode.inputFormat(forBus: 0)
            outputFormat = inputNode.outputFormat(forBus: 0)
        }
        FlowTrace.capture(
            "audioSession.active",
            "hwRate=\(Int(hardwareFormat.sampleRate)) hwChannels=\(hardwareFormat.channelCount) "
                + "outputRate=\(Int(outputFormat.sampleRate)) "
                + "sessionRate=\(Int(sessionSnapshot.sampleRate)) "
                + "route=\(sessionSnapshot.inputPortType)"
        )
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            FlowTrace.warn(
                "capture.hardwareFormat.invalid",
                "hwRate=\(hardwareFormat.sampleRate) hwChannels=\(hardwareFormat.channelCount)"
            )
            throw StartError.invalidHardwareFormat(
                sampleRate: hardwareFormat.sampleRate,
                channels: Int(hardwareFormat.channelCount)
            )
        }
        guard sessionSnapshot.sampleRate <= 0
                || abs(hardwareFormat.sampleRate - sessionSnapshot.sampleRate) < 1 else {
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

        let gateLock = gate
        let relay = streamRelay
        let preroll = prerollStore
        let levels = levelStore
        let proof = audioProofStore
        let tracker = drainTracker
        let tailCounter = tailSampleCounter
        let pcmStore = utterancePCMStore
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
            utterancePCMStore: pcmStore,
            frameStats: frameStats,
            drainPolicy: policy
        )
        // `format: nil` binds the tap to the input node's *live* format. Passing
        // an explicit (possibly stale) format here is what crashed the app on a
        // route change (48 kHz client vs 24 kHz hardware); nil can never mismatch.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil, block: tap)
        didInstallTap = true
        FlowTrace.capture(
            "tap.installed",
            "hwRate=\(Int(hardwareFormat.sampleRate)) targetRate=\(Int(resolvedTargetFormat.sampleRate)) "
                + "bufferSize=4096 format=live"
        )

        do {
            try await FlowAudioSessionCoordinator.shared.startEngine(
                FlowAudioEngineHandle(candidateEngine)
            )
        } catch {
            inputNode.removeTap(onBus: 0)
            didInstallTap = false
            await FlowAudioSessionCoordinator.shared.stopEngine(
                FlowAudioEngineHandle(candidateEngine)
            )
            FlowTrace.warn("capture.engine.startFailed", "error=\(error.localizedDescription)")
            throw StartError.engineStartFailed(error.localizedDescription)
        }
        audioEngine = candidateEngine
        activeRouteSnapshot = sessionSnapshot
        engineActivationCount += 1
        lastActivationAt = Date()
        FlowTrace.capture("engine.started", "running=\(audioEngine.isRunning ? 1 : 0)")
    }

    /// Tear down the engine and release the audio session.
    public func stop(releaseSession: Bool = true) {
        // Logged before teardown: in PiP keep-alive every utterance ends with a
        // stop(), which also discards the converter — so this line marks the
        // point after which the next press must rebuild the whole audio path.
        FlowTrace.capture(
            "stop",
            "wasRunning=\(isRunning ? 1 : 0) engineLive=\(engineIsLive ? 1 : 0) "
                + frameStats.snapshot().summary
        )
        removeSessionObservers()
        routeRecoveryTask?.cancel()
        routeRecoveryTask = nil
        gate.withLock { $0 = .idle }
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        streamRelay.finish()

        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        FlowAudioSessionCoordinator.shared.enqueueStopEngine(
            FlowAudioEngineHandle(audioEngine)
        )
        isRunning = false
        interrupted = false
        audioProofStore.reset()
        downsampler = nil
        targetFormat = nil
        hwFormat = nil
        activeRouteSnapshot = nil
        if releaseSession {
            FlowAudioSessionCoordinator.shared.deactivate()
        }
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
    public func reassertIfRunning() async -> Bool {
        guard isRunning else { return false }
        if routeFormatIsStable(), audioEngine.isRunning {
            do {
                _ = try await FlowAudioSessionCoordinator.shared.activateCapture()
                interrupted = false
                notifyEngineLiveChanged()
                FlowTrace.capture("reassert.ok", "engineLive=\(engineIsLive ? 1 : 0)")
                return engineIsLive
            } catch {
                FlowTrace.warn("capture.reassert.failed", "error=\(error.localizedDescription)")
            }
        }
        do {
            try await activateEngine()
            interrupted = false
            notifyEngineLiveChanged()
            FlowTrace.capture("reassert.rebuilt", "engineLive=\(engineIsLive ? 1 : 0)")
            return engineIsLive
        } catch {
            FlowTrace.warn("capture.reassert.failed", "error=\(error.localizedDescription)")
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
        if engineConfigurationObserver == nil {
            engineConfigurationObserver = center.addObserver(
                forName: .AVAudioEngineConfigurationChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard !self.isActivatingEngine else {
                        FlowTrace.capture(
                            "engineConfigurationChange.ignored",
                            "reason=activationInProgress"
                        )
                        return
                    }
                    if !self.routeFormatIsStable() || !self.audioEngine.isRunning {
                        self.scheduleRouteRecovery(reason: "engineConfigurationChange")
                    } else {
                        FlowTrace.capture(
                            "engineConfigurationChange.ignored",
                            "reason=stable"
                        )
                    }
                }
            }
        }
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        if let routeObserver { center.removeObserver(routeObserver) }
        if let interruptionObserver { center.removeObserver(interruptionObserver) }
        if let mediaResetObserver { center.removeObserver(mediaResetObserver) }
        if let engineConfigurationObserver { center.removeObserver(engineConfigurationObserver) }
        routeObserver = nil
        interruptionObserver = nil
        mediaResetObserver = nil
        engineConfigurationObserver = nil
    }

    private func handleMediaServicesReset() {
        guard isRunning else { return }
        log.info("Media services were reset — rebuilding engine and converter")
        FlowTrace.warn("capture.mediaServicesReset", frameStats.snapshot().summary)
        Task { @MainActor [weak self] in
            await self?.rebuildEngine()
        }
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard isRunning else { return }
        guard !isActivatingEngine else {
            FlowTrace.capture(
                "routeChange.ignored",
                "reason=\(reasonRaw ?? 0) activationInProgress=1"
            )
            return
        }
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        let formatIsStable = routeFormatIsStable()
        if FlowAudioRouteRecoveryPolicy.shouldRebuild(
            reasonRaw: reasonRaw,
            formatIsStable: formatIsStable,
            engineIsRunning: audioEngine.isRunning
        ) {
            log.info("Audio route changed (\(reasonRaw, privacy: .public)) — rebuilding engine")
            FlowTrace.capture(
                "routeChange.rebuild",
                "reason=\(reasonRaw) gate=\(gate.withLock { $0 }.label) "
                    + frameStats.snapshot().summary
            )
            scheduleRouteRecovery(reason: "route=\(reasonRaw)")
        } else {
            FlowTrace.capture(
                "routeChange.ignored",
                "reason=\(reason.rawValue) stable=\(formatIsStable ? 1 : 0)"
            )
        }
    }

    private func routeFormatIsStable() -> Bool {
        let session = AVAudioSession.sharedInstance()
        let sessionRate = session.sampleRate
        let inputRate = audioEngine.inputNode.inputFormat(forBus: 0).sampleRate
        guard sessionRate > 0, inputRate > 0 else { return false }
        guard abs(sessionRate - inputRate) < 1 else { return false }
        guard let activeRouteSnapshot else { return true }
        let currentInput = session.currentRoute.inputs.first
        return activeRouteSnapshot.inputPortUID == (currentInput?.uid ?? "")
            && activeRouteSnapshot.inputPortType == (currentInput?.portType.rawValue ?? "none")
    }

    private func scheduleRouteRecovery(reason: String) {
        guard isRunning else { return }
        routeRecoveryTask?.cancel()
        routeRecoveryTask = Task { @MainActor [weak self] in
            // Route notifications arrive in bursts while HFP negotiates its
            // final sample rate. Debounce before creating the new graph.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.routeRecoveryCount += 1
            FlowTrace.capture("routeRecovery.begin", "reason=\(reason)")
            await self.rebuildEngine()
        }
    }

    private func handleInterruption(typeRaw: UInt?, optionsRaw: UInt?) {
        guard let typeRaw,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
        switch type {
        case .began:
            log.info("Audio interruption began")
            FlowTrace.warn(
                "capture.interruption.began",
                "gate=\(gate.withLock { $0 }.label) \(frameStats.snapshot().summary)"
            )
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
            FlowTrace.capture("interruption.ended", "shouldResume=\(shouldResume ? 1 : 0)")
            if shouldResume {
                log.info("Audio interruption ended — resuming capture")
                Task { @MainActor [weak self] in
                    await self?.rebuildEngine()
                }
            }
        @unknown default:
            break
        }
    }

    /// Stop and rebuild the engine against the current route, keeping
    /// `isRunning` intact so the session survives the swap transparently.
    private func rebuildEngine() async {
        guard isRunning, !isRebuilding else {
            FlowTrace.capture(
                "rebuild.skipped",
                "running=\(isRunning ? 1 : 0) alreadyRebuilding=\(isRebuilding ? 1 : 0)"
            )
            return
        }
        isRebuilding = true
        defer { isRebuilding = false }
        do {
            try await activateEngine()
            notifyEngineLiveChanged()
            FlowTrace.capture("rebuild.done", "engineLive=\(engineIsLive ? 1 : 0)")
        } catch {
            isRunning = false
            activeRouteSnapshot = nil
            if didInstallTap {
                audioEngine.inputNode.removeTap(onBus: 0)
                didInstallTap = false
            }
            FlowAudioSessionCoordinator.shared.enqueueStopEngine(
                FlowAudioEngineHandle(audioEngine)
            )
            log.error("Engine rebuild failed: \(error.localizedDescription, privacy: .public)")
            FlowTrace.warn("capture.rebuild.failed", "error=\(error.localizedDescription)")
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
        utterancePCMStore.reset()
        // Counters are per-utterance: reset here so the report emitted at drain
        // describes only this press.
        let priorReport = frameStats.snapshot()
        frameStats.reset()
        // Bind the consumer before opening the gate so early tap frames
        // are not dropped on the floor.
        streamRelay.bind(continuation)
        let preroll = prerollStore.drain()
        streamRelay.replay(preroll)
        gate.withLock { $0 = .recording }
        let prerollSamples = preroll.reduce(0) { $0 + $1.samples.count }
        FlowTrace.capture(
            "beginUtterance",
            "engineLive=\(engineIsLive ? 1 : 0) recentRawAudio=\(engineHasRecentAudio(maxAge: 2) ? 1 : 0) "
                + "prerollBuffers=\(preroll.count) prerollSamples=\(prerollSamples) "
                + "prerollSeconds=\(FlowTrace.seconds(samples: prerollSamples)) "
                + "sinceLastActivationMs=\(Int(Date().timeIntervalSince(lastActivationAt) * 1000)) "
                + "priorIdle[\(priorReport.summary)]"
        )
        return stream
    }

    /// Drain trailing PCM after the user stops, then finish the ASR stream.
    public func endUtteranceAndDrain(
        policy: FlowCaptureTailDrainPolicy = .flowDefault
    ) async -> FlowCaptureDrainReport {
        let currentPhase = gate.withLock { $0 }
        guard currentPhase == .recording else {
            FlowTrace.warn(
                "capture.endUtterance.skipped",
                "gate=\(currentPhase.label) \(frameStats.snapshot().summary)"
            )
            return .skipped
        }

        drainPolicy = policy
        gate.withLock { $0 = .draining }
        drainTracker.beginDrain()

        let timing = await FlowUtteranceEndCoordinator.awaitTailCapture(
            tracker: drainTracker,
            policy: policy,
            pollIntervalNs: FlowCaptureConstants.drainPollIntervalNs
        )

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
            endedBySilence: timing.endedBySilence,
            tailSampleCount: tailSamples,
            postRollDurationSeconds: timing.postRollDurationSeconds
        )
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        FlowPipelineDiagnostics.logDrain(report)

        // The decisive line for "waveform moved but no text": compare the raw
        // frame count the waveform was drawn from against the samples that
        // actually reached the recogniser.
        let frames = frameStats.snapshot()
        if frames.isFeedStarved {
            FlowTrace.warn(
                "capture.endUtterance.feedStarved",
                "micDeliveredFrames=\(frames.framesReceived) butASRGotSamples=0 \(frames.summary)"
            )
        } else {
            FlowTrace.capture("endUtterance.done", frames.summary)
        }
        return report
    }

    /// Returns the utterance PCM accumulated during the last recording cycle.
    public func consumeUtteranceSamples() -> [Float] {
        utterancePCMStore.consume()
    }

    /// Immediate stop without tail drain (abort / session teardown).
    public func cancelUtterance() {
        FlowTrace.capture(
            "cancelUtterance",
            "gate=\(gate.withLock { $0 }.label) \(frameStats.snapshot().summary)"
        )
        gate.withLock { $0 = .idle }
        drainTracker.reset()
        tailSampleCounter.withLock { $0 = 0 }
        utterancePCMStore.reset()
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
        utterancePCMStore: FlowUtterancePCMStore,
        frameStats: FlowCaptureFrameStats,
        drainPolicy: FlowCaptureTailDrainPolicy
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            // Levels and the audio-proof timestamp come from the RAW buffer,
            // everything downstream from the converted one. `frameStats` bridges
            // the two so a mismatch (waveform alive, ASR starved) is reportable
            // instead of invisible — counters only, no logging on this thread.
            audioProofStore.markFrameReceived()
            frameStats.noteFrameReceived()
            levelStore.update(from: buffer, barCount: FlowCaptureConstants.levelBarCount)

            // The downsampler derives its converter from the *live* buffer
            // format (mid-session route changes handled transparently) and
            // returns a REUSED scratch buffer — no per-callback allocation
            // on the realtime thread. The snapshot below copies the samples
            // out before the next tap callback can overwrite the scratch.
            let outcome = downsampler.convertReusingScratch(buffer)
            guard case .converted(let outBuffer) = outcome else {
                if case .failed(let failure, let sourceRate, let inFrames, let wanted) = outcome {
                    frameStats.noteDropped(
                        failure: failure,
                        sourceRate: sourceRate,
                        inputFrames: inFrames,
                        wantedFrames: wanted
                    )
                }
                return
            }

            let snapshot = AudioBufferSnapshot(buffer: outBuffer)
            guard !snapshot.samples.isEmpty else {
                frameStats.noteDropped(
                    failure: .emptyOutput,
                    sourceRate: buffer.format.sampleRate,
                    inputFrames: Int(buffer.frameLength),
                    wantedFrames: 0
                )
                return
            }

            let phase = gate.withLock { $0 }
            switch phase {
            case .recording, .draining:
                frameStats.noteConverted(samples: snapshot.samples.count, reachedASR: true)
                utterancePCMStore.append(snapshot.samples)
                streamRelay.yield(snapshot)
                if phase == .draining {
                    drainTracker.noteAudio(samples: snapshot.samples, policy: drainPolicy)
                    tailSampleCounter.withLock { $0 += snapshot.samples.count }
                }
            case .idle:
                frameStats.noteConverted(samples: snapshot.samples.count, reachedASR: false)
                prerollStore.append(snapshot)
            }
        }
    }
}
