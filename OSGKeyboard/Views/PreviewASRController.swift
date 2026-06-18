// PreviewASRController.swift
// OSGKeyboard · Main App (Debug)
//
// Self-contained ASR controller for the in-app keyboard preview sheet.
// Owns its own AVAudioEngine + AVAudioSession, downsamples to 16 kHz
// mono Float32, and feeds the `AudioBufferSnapshot` stream to the
// shared `ASRService` (the same pipeline the real keyboard extension
// uses, so the preview exercises the *real* iOS speech APIs, not a
// stub). Without this the in-app preview was a hardcoded transcript
// and "did you actually call SFSpeechRecognizer?" was a fair review
// note.
//
// Why not reuse `AudioCaptureService` from the extension? It lives in
// `OSGKeyboardExt`, an `app-extension` target — the main app can't
// import its symbols. We could move it to `OSGKeyboardShared`, but
// `AVAudioSession` lifecycle differs enough between a keyboard
// extension (no background, no recording entitlement surprise) and a
// foreground app that a copy here is the lesser evil.

import Foundation
import AVFoundation
import Speech
import OSGKeyboardShared

@MainActor
final class PreviewASRController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case requestingPermission
        case recording
        case processing
        case denied(String)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Normalized 0...1 RMS for the disc level meter. Polled from the
    /// audio tap via `Task { @MainActor in ... }` — the tap itself
    /// runs on a real-time audio thread, so we never touch published
    /// state from there.
    @Published private(set) var level: Double = 0
    @Published private(set) var currentPartial: String = ""
    @Published private(set) var errorMessage: String?

    /// Set when a `.final` ASR event lands. The owning sheet observes
    /// this and appends the text to its textbox, then clears it so the
    /// next recording starts from zero.
    @Published var lastFinal: String = ""

    private let asr: ASRService = ASRServiceFactory.make()
    private let audioEngine = AVAudioEngine()
    private var asrTask: Task<Void, Never>?
    private var bufferContinuation: AsyncStream<AudioBufferSnapshot>.Continuation?
    private var didConfigureAudioSession = false
    private var didInstallTap = false

    func start(locale: Locale) async {
        // Re-entry guard: ignore taps that arrive while we're already
        // running. (The sheet's `cyclePhase` is also guarded, but
        // async race windows are easier to lock down here.)
        switch phase {
        case .recording, .requestingPermission, .processing:
            return
        default:
            break
        }
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
        if !didConfigureAudioSession {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord,
                                        mode: .measurement,
                                        options: [.defaultToSpeaker, .allowBluetoothHFP])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                didConfigureAudioSession = true
            } catch {
                phase = .error("Audio session 错误 · Audio session error: \(error.localizedDescription)")
                return
            }
        }

        // 4. Spin up the engine + ASR.
        phase = .recording
        startEngineAndASR(locale: locale)
    }

    func stop() {
        asrTask?.cancel()
        asrTask = nil
        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        bufferContinuation?.finish()
        bufferContinuation = nil
        if phase == .recording {
            phase = .processing
        }
        // Deactivate so the user's music resumes if the preview is
        // dismissed mid-recording.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
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
        let hwFormat = inputNode.outputFormat(forBus: 0)
        let targetSampleRate: Double = 16_000
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            phase = .error("无法创建 16 kHz 音频格式")
            return
        }
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            phase = .error("无法创建音频转换器")
            return
        }

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        self.bufferContinuation = continuation

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
        let onSnapshot: @Sendable (AudioBufferSnapshot) -> Void = { [weak self] snapshot in
            Task { @MainActor [weak self] in
                self?.bufferContinuation?.yield(snapshot)
            }
        }
        let tap = Self.makeAudioTapBlock(
            converter: converter,
            targetFormat: targetFormat,
            hwFormat: hwFormat,
            targetSampleRate: targetSampleRate,
            onMeter: onMeter,
            onSnapshot: onSnapshot
        )
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat, block: tap)
        didInstallTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            phase = .error("无法启动音频引擎 · Engine start failed: \(error.localizedDescription)")
            return
        }

        // 5. Wire up ASR.
        let events = asr.transcribe(
            stream: stream,
            locale: locale,
            requiresOnDevice: false
        )
        asrTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in events {
                switch event {
                case .capability:
                    // Could surface on-device vs cloud here; preview
                    // doesn't need it.
                    break
                case .partial(let s):
                    self.currentPartial = s
                case .final(let s):
                    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastFinal = trimmed
                    self.currentPartial = ""
                    if !trimmed.isEmpty {
                        self.phase = .idle
                    } else {
                        // Empty final: nothing recognized. Return to idle
                        // without triggering a textbox insert.
                        self.phase = .idle
                    }
                case .error(let m):
                    self.errorMessage = m
                    self.phase = .error(m)
                }
            }
        }
    }

    // MARK: - Permission helpers (nonisolated)
    //
    // `SFSpeechRecognizer.requestAuthorization` and (iOS < 17)
    // `AVAudioSession.requestRecordPermission` deliver their callbacks
    // on a TCC reply queue, NOT the main queue. If we wrap those
    // callbacks inline in `start(locale:)` — which is `@MainActor` —
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
    // `closure #1 in closure #2 in PreviewASRController.start(locale:)`.
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
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:               return true
            case .denied:                return false
            case .undetermined:          return await AVAudioApplication.requestRecordPermission()
            @unknown default:            return false
            }
        } else {
            return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission(
                    Self.makeMicAuthHandler(continuation: cont)
                )
            }
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

    private nonisolated static func makeMicAuthHandler(
        continuation: CheckedContinuation<Bool, Never>
    ) -> @Sendable (Bool) -> Void {
        return { granted in
            continuation.resume(returning: granted)
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
        targetSampleRate: Double,
        onMeter: @Sendable @escaping (Double) -> Void,
        onSnapshot: @Sendable @escaping (AudioBufferSnapshot) -> Void
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        // `@Sendable` on the returned closure makes the Sendable
        // conformance explicit. `AVAudioNodeTapBlock` is declared as
        // a plain escaping closure in the SDK; we cast at the call
        // site via `as @Sendable`.
        return { buffer, _ in
            // Downsample + extract samples + compute RMS in one pass.
            let ratio = targetSampleRate / hwFormat.sampleRate
            let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 0.5)
            guard outCapacity > 0,
                  let converted = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: outCapacity
                  ) else { return }

            var error: NSError?
            var supplied = false
            converter.convert(to: converted, error: &error) { _, outStatus in
                if supplied {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return buffer
            }
            if error != nil { return }

            let n = Int(converted.frameLength)
            var samples = [Float](repeating: 0, count: n)
            var sumSquares: Float = 0
            if let channelData = converted.floatChannelData?[0] {
                for i in 0..<n {
                    let v = channelData[i]
                    samples[i] = v
                    sumSquares += v * v
                }
            }
            let rms = n > 0 ? sqrtf(sumSquares / Float(n)) : 0
            // RMS for speech is typically 0.02-0.2; the 4x gain pushes
            // normal speech into the 0.4-0.8 range for the disc meter.
            let meter = min(Double(rms) * 4.0, 1.0)
            let snapshot = AudioBufferSnapshot(samples: samples, sampleRate: targetSampleRate)
            onMeter(meter)
            onSnapshot(snapshot)
        }
    }
}
