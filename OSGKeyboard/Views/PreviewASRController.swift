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

        // 1. Microphone permission.
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:               micGranted = true
            case .denied:                micGranted = false
            case .undetermined:          micGranted = await AVAudioApplication.requestRecordPermission()
            @unknown default:            micGranted = false
            }
        } else {
            micGranted = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        guard micGranted else {
            phase = .denied("麦克风被拒绝 · Mic denied")
            return
        }

        // 2. Speech recognition permission.
        let speechGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechGranted else {
            phase = .denied("语音识别被拒绝 · Speech denied")
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

        // Tap the hardware input. The closure runs on a real-time audio
        // thread, so it must do the minimum work needed to produce a
        // snapshot and then hand off to the main actor for state updates.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
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
            // RMS for speech is typically 0.02-0.2; the 4x gain here
            // pushes normal speech into the 0.4-0.8 range for the
            // disc meter so it visibly responds.
            let meter = min(Double(rms) * 4.0, 1.0)
            let snapshot = AudioBufferSnapshot(samples: samples, sampleRate: targetSampleRate)

            // Hop to main for state updates.
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Lightweight smoothing so the disc ring doesn't jitter.
                self.level = self.level * 0.55 + meter * 0.45
                self.bufferContinuation?.yield(snapshot)
            }
        }
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
}
