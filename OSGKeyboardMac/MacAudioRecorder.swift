// MacAudioRecorder.swift
// OSGKeyboard · Mac
//
// Captures microphone audio via AVAudioEngine and resamples it to the
// 16 kHz mono Float32 buffer the cloud ASR clients expect. The tap
// callback runs on the audio render thread, so sample accumulation is
// guarded by a lock and the type is `@unchecked Sendable`.

@preconcurrency import AVFoundation

final class MacAudioRecorder: @unchecked Sendable {
    enum RecorderError: Error, LocalizedError {
        case converterUnavailable
        case microphoneAccessDenied

        var errorDescription: String? {
            switch self {
            case .converterUnavailable:
                return "无法初始化音频转换器 / Failed to initialize audio converter"
            case .microphoneAccessDenied:
                return "麦克风权限被拒绝——请在「系统设置 → 隐私与安全性 → 麦克风」中启用"
                    + " / Microphone access denied — enable it in System Settings"
                    + " → Privacy & Security → Microphone"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!
    private var converter: AVAudioConverter?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var snapshotContinuation: AsyncStream<AudioBufferSnapshot>.Continuation?
    private var isRunning = false
    /// Hard cap on accumulated audio: 10 minutes @16 kHz ≈ 38 MB of Float32.
    /// Recording is push-to-talk, but a stuck hotkey (or a latched Option
    /// key) would otherwise grow this buffer without bound; past the cap we
    /// keep the newest audio (drop from the front) so the take still ends
    /// with what the user last said.
    private static let maxSampleCount = 10 * 60 * 16_000
    /// Trim hysteresis: dropping from the front is an O(n) memmove of the
    /// whole ~38 MB buffer, done under the same lock the UI's level poll
    /// takes — doing it on EVERY tap callback once capped would stall the
    /// render thread ~12×/s. Let the buffer overshoot by 30 s and trim the
    /// whole excess in one move instead.
    private static let trimHysteresisSamples = 30 * 16_000
    private var smoothedLevel: Float = 0
    /// One-shot flag for the converter pull block. Taps are serialized per
    /// bus, so a plain instance property (not a captured local) is safe here.
    private var didProvideInput = false

    /// Normalised input level (0…1), smoothed for a calm waveform.
    /// Read from the main thread by a polling timer while recording.
    func level() -> Float {
        lock.withLock { smoothedLevel }
    }

    /// Resolves microphone authorization before capture. Prompts on first
    /// use; throws `microphoneAccessDenied` once the user has declined so
    /// failures surface as a permission problem, not an empty transcription.
    private static func ensureMicrophoneAccess() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw RecorderError.microphoneAccessDenied
            }
        case .denied, .restricted:
            throw RecorderError.microphoneAccessDenied
        @unknown default:
            throw RecorderError.microphoneAccessDenied
        }
    }

    func start() async throws {
        try await Self.ensureMicrophoneAccess()
        try startEngine()
    }

    /// Live 16 kHz mono snapshots for streaming ASR while the mic is open.
    /// The stream is finished automatically in `stop()`.
    func makeSnapshotStream() -> AsyncStream<AudioBufferSnapshot> {
        AsyncStream { continuation in
            lock.withLock {
                snapshotContinuation?.finish()
                snapshotContinuation = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.snapshotContinuation = nil
                }
            }
        }
    }

    private func startEngine() throws {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            snapshotContinuation?.finish()
            snapshotContinuation = nil
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.appendResampled(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stops capture and returns the accumulated 16 kHz mono samples.
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        return lock.withLock {
            snapshotContinuation?.finish()
            snapshotContinuation = nil
            let out = samples
            samples.removeAll(keepingCapacity: false)
            return out
        }
    }

    private func appendResampled(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { [self] _, statusPointer in
            if didProvideInput {
                statusPointer.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            statusPointer.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let channel = output.floatChannelData else { return }

        let frameCount = Int(output.frameLength)
        guard frameCount > 0 else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel[0], count: frameCount))

        // RMS → rough 0…1 level with an attack/decay smoothing so the UI
        // waveform breathes rather than jitters.
        var sumSquares: Float = 0
        for sample in chunk { sumSquares += sample * sample }
        let rms = (sumSquares / Float(frameCount)).squareRoot()
        let normalized = min(1, max(0, rms * 12))

        lock.withLock {
            samples.append(contentsOf: chunk)
            if samples.count > Self.maxSampleCount + Self.trimHysteresisSamples {
                samples.removeFirst(samples.count - Self.maxSampleCount)
            }
            let factor: Float = normalized > smoothedLevel ? 0.5 : 0.15
            smoothedLevel += (normalized - smoothedLevel) * factor
            snapshotContinuation?.yield(
                AudioBufferSnapshot(samples: chunk, sampleRate: 16_000)
            )
        }
    }
}
