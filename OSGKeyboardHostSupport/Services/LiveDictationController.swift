// LiveDictationController.swift
// OSGKeyboard · HostSupport
//
// Unified on-device dictation session: mic capture + iOS 26 SpeechAnalyzer.
// Retained for foreground preview and one-shot handoff surfaces that need
// live ASR without duplicating the host-owned audio pipeline.
//
// The *primary* voice-session path is `FlowSessionManager` +
// `FlowContinuousCapture`; the keyboard extension consumes its results
// through `FlowSessionBridge`.
//
// This class is still imported by:
//   - `OSGKeyboard/Views/KeyboardPreviewSheet.swift` (in-app preview)
//   - `OSGKeyboardTests/PreviewASRControllerStateTests.swift`
//
// Do NOT remove without updating those call sites.
// Owns its own AVAudioEngine + AVAudioSession, downsamples to 16 kHz
// mono Float32 on the audio thread, and feeds `AudioBufferSnapshot` to
// the HostSupport `ASRService`, so previews exercise the real iOS
// speech APIs instead of a stub.
//
// This stays in HostSupport because foreground `AVAudioSession`
// lifecycle and recording ownership do not belong in the keyboard
// extension or the platform-neutral Shared target.

import Foundation
import AVFoundation
import Speech
import os
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

private enum LiveCaptureGatePhase: Equatable {
    case idle
    case recording
    case draining
}

/// Thread-safe relay so the AVAudioEngine tap can yield snapshots without
/// hopping through `@MainActor` (which adds latency and can reorder frames).
private final class CaptureStreamRelay: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var continuation: AsyncStream<AudioBufferSnapshot>.Continuation?

    func bind(_ continuation: AsyncStream<AudioBufferSnapshot>.Continuation) {
        lock.withLock { self.continuation = continuation }
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

@MainActor
public final class LiveDictationController: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case processing
        case denied(String)
        case error(String)
    }

    @Published public private(set) var phase: Phase = .idle
    /// Normalized 0...1 RMS for the disc level meter. Polled from the
    /// audio tap via `Task { @MainActor in ... }` — the tap itself
    /// runs on a real-time audio thread, so we never touch published
    /// state from there.
    @Published public private(set) var level: Double = 0
    @Published public private(set) var currentPartial: String = ""
    @Published public private(set) var errorMessage: String?

    /// Set when a `.final` ASR event lands. The owning sheet observes
    /// this and appends the text to its textbox, then clears it so the
    /// next recording starts from zero.
    @Published public var lastFinal: String = ""

    private let asr: ASRService
    private var audioEngine = AVAudioEngine()
    /// `internal` (not `private`) so the regression test in
    /// `OSGKeyboardTests/PreviewASRControllerStateTests.swift` can
    /// install a known consumer task and assert `stop()` doesn't
    /// cancel it. The class is `@MainActor`-isolated, so the
    /// natural Swift 6 isolation rules still prevent production
    /// code outside the class from racing on it.
    public var asrTask: Task<Void, Never>?
    private let streamRelay = CaptureStreamRelay()
    private var chunkedPipeline: ChunkedUtterancePipeline?
    private let captureGate = OSAllocatedUnfairLock(initialState: LiveCaptureGatePhase.idle)
    private let drainTracker = FlowCaptureDrainTracker()
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var hwFormat: AVAudioFormat?
    private var didConfigureAudioSession = false
    private var didInstallTap = false

    public init(asr: ASRService? = nil) {
        self.asr = asr ?? ASRServiceFactory.make(store: AppGroupStore())
    }

    /// Start dictation using a persisted settings locale id (`auto`, `zh-Hans`, …).
    public func start(localeId: String) async {
        await start(locale: SpeechLocaleResolver.resolve(localeId))
    }

    public func start(locale: Locale) async {
        // Re-entry guard: ignore taps that arrive while we're already
        // running. (The sheet's `cyclePhase` is also guarded, but
        // async race windows are easier to lock down here.)
        switch phase {
        case .recording, .requestingPermission, .processing:
            return
        default:
            break
        }
        // Cancel any leftover consumer task from a previous recording.
        // Normally `stop()` lets the task run to completion (so it can
        // see the `.final` and transition out of `.processing`), but if
        // the user smashed the disc twice — stop, then immediately
        // start — the previous task might still be draining. Cancel it
        // here so we don't have two consumer tasks fighting over the
        // same `events` stream.
        asrTask?.cancel()
        asrTask = nil
        if let pipeline = chunkedPipeline {
            Task { await pipeline.cancel() }
        }
        chunkedPipeline = nil
        teardownCapturePipeline()
        phase = .requestingPermission
        currentPartial = ""
        lastFinal = ""
        errorMessage = nil
        level = 0

        // 1. Microphone permission. The helper is `nonisolated` so the
        // (iOS < 17) callback closure does not inherit `@MainActor` —
        // `AVAudioSession.requestRecordPermission` delivers on a TCC
        // reply queue, and a `@MainActor`-inferred closure body there
        // hits `dispatch_assert_queue` in `_swift_task_checkIsolatedSwift`.
        let micGranted = await Self.requestMicrophonePermission()
        guard micGranted else {
            phase = .denied(NSLocalizedString("keyboard.denied.mic", comment: ""))
            return
        }

        // 2. Speech recognition permission. Same reasoning as above:
        // the callback fires on TCC's reply queue, NOT the main queue.
        let speechGranted = await Self.requestSpeechRecognitionPermission()
        guard speechGranted else {
            phase = .denied(NSLocalizedString("keyboard.denied.speech", comment: ""))
            return
        }

        // 3. Audio session — only configure once per process.
        //
        // On device we use `.playAndRecord` + `.voiceChat` so Apple Voice
        // Processing can suppress competing talkers. The iOS Simulator's
        // speaker reports a 0 Hz output format, so `.playAndRecord` fails
        // with `kAudioUnitErr_FormatNotSupported` (-10851); keep `.record`
        // there so preview still works under CoreSimulator.
        if !didConfigureAudioSession {
            do {
                let session = AVAudioSession.sharedInstance()
                #if targetEnvironment(simulator)
                try session.setCategory(.record, mode: .default, options: [])
                #else
                try session.setCategory(
                    .playAndRecord,
                    mode: FlowCaptureVoiceProcessing.captureMode,
                    options: FlowCaptureVoiceProcessing.captureOptions
                )
                #endif
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                #if !targetEnvironment(simulator)
                FlowCaptureVoiceProcessing.preferNearTalkBuiltInMic(on: session)
                #endif
                didConfigureAudioSession = true
            } catch {
                debug("audio session failed: \(error.localizedDescription)")
                phase = .error(String.localizedStringWithFormat(
                    NSLocalizedString("preview.error.audioSession", comment: ""),
                    error.localizedDescription
                ))
                return
            }
        }
        // The route may have changed while the preview was closed. A fresh
        // engine created after session activation avoids a stale input node.
        audioEngine = AVAudioEngine()
        // Enable VP before reading hardware format — RemoteIO rate can shift.
        _ = FlowCaptureVoiceProcessing.enableVoiceProcessing(on: audioEngine)

        // 4. Spin up the engine + ASR.
        phase = .recording
        startEngineAndASR(locale: locale)
    }

    public func stop() {
        // Don't `asrTask?.cancel()` here — see the comment in
        // `startEngineAndASR` for the full rationale. Short version:
        // cancelling the consumer task at the same moment we close the
        // audio stream also triggers the producer's
        // `continuation.onTermination → self?.cancel()` cascade, which
        // marks the producer's outer task as cancelled and skips the
        // `.final` event. The UI is then left in `.processing` forever
        // because no one schedules the transition out. The consumer
        // task naturally exits when `events` finishes, so the right
        // thing is to let it run.
        //
        // If a previous `asrTask` is somehow still running (e.g. the
        // user smashed the disc twice quickly), `start()` cancels it
        // at the entry point as a safety net.
        let partial = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty && lastFinal.isEmpty {
            lastFinal = partial
            currentPartial = ""
        }
        if phase == .recording {
            phase = .processing
        }

        Task { @MainActor [weak self] in
            await self?.drainTailAndTeardownCapture()
        }

        // Safety net: if the ASR pipeline never produces a `.final`
        // (analyzer hang, system glitch, dropped continuation), force
        // the UI back to idle after a short delay so the user isn't
        // stuck. Normal recordings complete well under a second, so
        // the 3-second budget is only hit on the unhappy path; if the
        // pipeline finishes first and flips the phase to `.idle` (or
        // `.error`), the check below no-ops.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            if self.phase == .processing {
                let stalePartial = self.currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stalePartial.isEmpty, self.lastFinal.isEmpty {
                    self.debug("processing timeout, using partial")
                    self.lastFinal = stalePartial
                    self.currentPartial = ""
                }
                self.phase = .idle
            }
        }
    }

    public func reset() {
        // Called by the sheet after appending `lastFinal` to the textbox,
        // so the next recording can produce a fresh final without us
        // double-appending.
        lastFinal = ""
        if phase == .processing {
            phase = .idle
        }
    }

    // MARK: - Engine + ASR

    private func startEngineAndASR(locale: Locale) {
        let inputNode = audioEngine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)

        // Pre-flight check: a placeholder / unconfigured input bus
        // reports `sampleRate == 0` (or `channelCount == 0`).
        // `installTap` on such a bus traps with "Failed to create
        // tap due to format mismatch" (an NSException, not a Swift
        // `Error`, so we can't `try`/`catch` it). The safest fix
        // is to refuse the tap up front and surface a clear
        // `.error` phase instead of crashing the app. We've seen
        // this on the iOS Simulator when the host's microphone
        // permission isn't granted to CoreSimulator, and on
        // devices where the audio session is in an unexpected
        // state from a previous foreground/background transition.
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            debug("invalid hardware format sr=\(hwFormat.sampleRate) ch=\(hwFormat.channelCount)")
            phase = .error(
                String.localizedStringWithFormat(
                    NSLocalizedString("preview.error.micUnavailable", comment: ""),
                    hwFormat.sampleRate,
                    Int(hwFormat.channelCount)
                )
            )
            return
        }

        let targetSampleRate: Double = 16_000
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            phase = .error(NSLocalizedString("preview.error.formatCreate", comment: ""))
            return
        }
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            debug("converter creation failed")
            phase = .error(NSLocalizedString("preview.error.converterCreate", comment: ""))
            return
        }

        audioConverter = converter
        self.targetFormat = targetFormat
        self.hwFormat = hwFormat
        drainTracker.reset()
        captureGate.withLock { $0 = .recording }

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        streamRelay.bind(continuation)

        // Tap the hardware input. The closure passed to `installTap` runs
        // on the AVAudioEngine real-time audio thread. In Swift 6 strict
        // concurrency, a closure literal defined inside a `@MainActor`
        // method inherits `@MainActor` isolation, which would trip
        // `dispatch_assert_queue_fail` on first invocation from the
        // audio thread. The fix is to build the actual tap body in a
        // `nonisolated` helper (`makeAudioTapBlock`) and have the
        // installTap closure be a single function reference — function
        // references never carry inferred isolation, so the dispatch
        // runtime is happy and the body runs wherever AVAudioEngine
        // wants it (the audio thread).
        let onMeter: @Sendable (Double) -> Void = { [weak self] meter in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Lightweight smoothing so the disc ring doesn't jitter.
                self.level = self.level * 0.55 + meter * 0.45
            }
        }
        let relay = streamRelay
        let gate = captureGate
        let tracker = drainTracker
        let policy = FlowCaptureTailDrainPolicy.flowDefault
        let onSnapshot: @Sendable (AudioBufferSnapshot) -> Void = { snapshot in
            let phase = gate.withLock { $0 }
            guard phase == .recording || phase == .draining else { return }
            relay.yield(snapshot)
            if phase == .draining {
                tracker.noteAudio(samples: snapshot.samples, policy: policy)
            }
        }
        let tap = Self.makeAudioTapBlock(
            converter: converter,
            targetFormat: targetFormat,
            hwFormat: hwFormat,
            onMeter: onMeter,
            onSnapshot: onSnapshot
        )
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat, block: tap)
        didInstallTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            debug("audio engine start failed: \(error.localizedDescription)")
            phase = .error(String.localizedStringWithFormat(
                NSLocalizedString("preview.error.engineStart", comment: ""),
                error.localizedDescription
            ))
            return
        }

        // 5. Pipelined ASR (same chunk path as Flow host).
        let pipeline = ChunkedUtterancePipeline(asr: asr, locale: locale)
        chunkedPipeline = pipeline
        asrTask = Task.detached(priority: .userInitiated) { [weak controller = self] in
            let outcome = await pipeline.transcribe(stream: stream) { partial in
                Task { @MainActor in
                    controller?.currentPartial = partial
                }
            }
            // Re-bind `controller` inside the `@MainActor` block so the
            // weak reference is captured under the right isolation. Swift
            // 6 strict concurrency otherwise complains about a
            // task-isolated reference escaping into a main-actor closure.
            await MainActor.run { [weak controller] in
                guard let controller else { return }
                switch outcome {
                case .success(let success):
                    let trimmed = success.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        controller.lastFinal = trimmed
                        controller.currentPartial = ""
                    }
                    if controller.phase == .processing || controller.phase == .recording {
                        controller.phase = .idle
                    }
                case .failure(let message):
                    controller.debug("asr failed messageLen=\(message.count)")
                    controller.teardownCapturePipeline()
                    controller.errorMessage = message
                    controller.phase = .error(message)
                case .cancelled:
                    if controller.phase == .processing {
                        controller.phase = .idle
                    }
                }
            }
        }
    }

    // MARK: - Permission helpers (nonisolated)
    //
    // `SFSpeechRecognizer.requestAuthorization` delivers its callback
    // on a TCC reply queue, NOT the main queue. If we wrap that
    // callback inline in `start(locale:)` — which is `@MainActor` —
    // Swift 6 strict concurrency infers the closure body as
    // `@MainActor`, and the runtime crashes on
    // `dispatch_assert_queue` in `_swift_task_checkIsolatedSwift` as
    // soon as TCC calls us back.
    //
    // The first attempt (commit `e8a0310`) extracted the entire
    // permission request into a `nonisolated static func` helper.
    // That worked in isolation, but the Swift 6 optimizer
    // inlined those helpers back into `start(locale:)`. After
    // inlining, the `withCheckedContinuation` body and the
    // `requestAuthorization` callback were re-typed in the
    // `@MainActor` context of the caller, and the runtime
    // assertion came right back — same crash, different symbol:
    // `closure #1 in closure #2 in LiveDictationController.start(locale:)`.
    //
    // The fix that survives inlining is the *function-reference*
    // pattern, the same one used for `installTap` in
    // `makeAudioTapBlock` below. The callback is built in a
    // `nonisolated` static helper that takes a `CheckedContinuation`
    // and returns the `(Status) -> Void` handler. The body of that
    // helper has no enclosing actor, so the closure is created in
    // nonisolated context. When TCC calls us back, the runtime
    // sees a nonisolated closure on a non-main queue and is happy.
    //
    // `cont.resume(...)` is itself thread-safe on
    // `CheckedContinuation`, so we don't need to hop back to the
    // main actor before resuming.

    private nonisolated static func requestMicrophonePermission() async -> Bool {
        // iOS 17+ API; the iOS < 17 fallback (`AVAudioSession.recordPermission`
        // + `requestRecordPermission` callback) is gone now that the
        // deployment target is iOS 26.
        switch AVAudioApplication.shared.recordPermission {
        case .granted:               return true
        case .denied:                return false
        case .undetermined:          return await AVAudioApplication.requestRecordPermission()
        @unknown default:            return false
        }
    }

    private nonisolated static func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization(
                Self.makeSpeechAuthHandler(continuation: cont)
            )
        }
    }

    private nonisolated static func makeSpeechAuthHandler(
        continuation: CheckedContinuation<Bool, Never>
    ) -> @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void {
        return { status in
            continuation.resume(returning: status == .authorized)
        }
    }

    // MARK: - Audio tap (nonisolated, runs on AVAudioEngine render thread)
    //
    // `AVAudioNode.installTap`'s callback fires on the audio engine's
    // real-time render thread. In Swift 6 strict concurrency, a closure
    // literal defined inside a `@MainActor` method inherits `@MainActor`
    // isolation — and `dispatch_assert_queue_fail` fires the moment
    // the runtime tries to dispatch that closure on a non-main queue.
    //
    // The trick is to build the actual tap body in a `nonisolated`
    // function and have the installTap closure be a *function reference*
    // to that helper. Function references never carry inferred
    // isolation, so the dispatch runtime is satisfied and the body
    // runs wherever AVAudioEngine wants. State updates to
    // `self.level` and the AsyncStream continuation hop back to the
    // main actor via `Task { @MainActor in … }`, which is itself
    // safe to call from a non-isolated context.
    private nonisolated static func makeAudioTapBlock(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        hwFormat: AVAudioFormat,
        onMeter: @Sendable @escaping (Double) -> Void,
        onSnapshot: @Sendable @escaping (AudioBufferSnapshot) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        // `@Sendable` on the returned closure makes the Sendable
        // conformance explicit. `AVAudioNodeTapBlock` is declared as
        // a plain escaping closure in the SDK; we cast at the call
        // site via `as @Sendable`.
        return { buffer, _ in
            // 1) Level meter from raw hardware buffer.
            let n = Int(buffer.frameLength)
            var sumSquares: Float = 0
            if let channelData = buffer.floatChannelData?[0], n > 0 {
                for i in 0..<n {
                    let v = channelData[i]
                    sumSquares += v * v
                }
            }
            let rms = n > 0 ? sqrtf(sumSquares / Float(n)) : 0
            let meter = min(Double(rms) * 4.0, 1.0)
            onMeter(meter)

            // 2) Downsample to the 16 kHz mono Float32 format expected by
            // HostSupport ASR and Apple's `considering:` hint.
            let outFrames = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / hwFormat.sampleRate
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
            onSnapshot(snapshot)
        }
    }

    private func drainTailAndTeardownCapture() async {
        let beganDrain = captureGate.withLock { phase -> Bool in
            switch phase {
            case .recording:
                phase = .draining
                return true
            case .draining, .idle:
                return false
            }
        }
        guard beganDrain else { return }

        drainTracker.beginDrain()

        let policy = FlowCaptureTailDrainPolicy.flowDefault
        _ = await FlowUtteranceEndCoordinator.awaitTailCapture(
            tracker: drainTracker,
            policy: policy
        )

        // Trailing speech is preserved by the live `.draining` forwarding
        // loop above. We deliberately do NOT signal `.endOfStream` to the
        // converter to squeeze its internal filter tail: that both races the
        // still-running audio-thread tap on the same non-thread-safe converter
        // and (in reused-converter paths) permanently locks it. The dropped
        // tail is sub-millisecond and inaudible.
        streamRelay.finish()
        teardownCaptureEngine()
        captureGate.withLock { $0 = .idle }
        drainTracker.reset()
        audioConverter = nil
        targetFormat = nil
        hwFormat = nil

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func teardownCaptureEngine() {
        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func teardownCapturePipeline() {
        teardownCaptureEngine()
        streamRelay.finish()
    }

    private func debug(_ message: String) {
        #if DEBUG
        print("🎙️[LiveDictationController] \(message)")
        #endif
    }
}
