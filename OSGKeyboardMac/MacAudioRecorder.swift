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

        var errorDescription: String? {
            switch self {
            case .converterUnavailable:
                return "无法初始化音频转换器 / Failed to initialize audio converter"
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
    private var isRunning = false
    private var smoothedLevel: Float = 0
    /// One-shot flag for the converter pull block. Taps are serialized per
    /// bus, so a plain instance property (not a captured local) is safe here.
    private var didProvideInput = false

    /// Normalised input level (0…1), smoothed for a calm waveform.
    /// Read from the main thread by a polling timer while recording.
    func level() -> Float {
        lock.withLock { smoothedLevel }
    }

    func start() throws {
        lock.withLock { samples.removeAll(keepingCapacity: true) }

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
            let factor: Float = normalized > smoothedLevel ? 0.5 : 0.15
            smoothedLevel += (normalized - smoothedLevel) * factor
        }
    }
}
