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
}

/// Thread-safe relay for utterance-scoped ASR snapshots.
private final class FlowCaptureStreamRelay: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var continuation: AsyncStream<AudioBufferSnapshot>.Continuation?

    func bind(_ continuation: AsyncStream<AudioBufferSnapshot>.Continuation) {
        lock.withLock { self.continuation = continuation }
    }

    func yield(_ snapshot: AudioBufferSnapshot) {
        lock.withLock { continuation?.yield(snapshot) }
    }

    func finish() {
        lock.withLock {
            continuation?.finish()
            continuation = nil
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
    private let levelStore = FlowLevelStore(barCount: FlowCaptureConstants.levelBarCount)
    private let isUtteranceActive = OSAllocatedUnfairLock(initialState: false)

    private var didInstallTap = false
    private var isRunning = false

    public init() {}

    public var running: Bool { isRunning }

    /// Configure `.playAndRecord`, install a permanent input tap, start the engine.
    public func start() throws {
        guard !isRunning else { return }

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
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw StartError.invalidHardwareFormat(
                sampleRate: hwFormat.sampleRate,
                channels: Int(hwFormat.channelCount)
            )
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: FlowCaptureConstants.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw StartError.formatCreateFailed
        }
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw StartError.converterCreateFailed
        }

        if !didInstallTap {
            let utteranceFlag = isUtteranceActive
            let relay = streamRelay
            let levels = levelStore
            let tap = Self.makeAudioTapBlock(
                converter: converter,
                targetFormat: targetFormat,
                hwFormat: hwFormat,
                utteranceFlag: utteranceFlag,
                levelStore: levels,
                streamRelay: relay
            )
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat, block: tap)
            didInstallTap = true
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw StartError.engineStartFailed(error.localizedDescription)
        }
        isRunning = true
    }

    /// Tear down the engine and release the audio session.
    public func stop() {
        isUtteranceActive.withLock { $0 = false }
        streamRelay.finish()

        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    /// Begin forwarding downsampled buffers to ASR for one utterance.
    public func beginUtterance() -> AsyncStream<AudioBufferSnapshot> {
        isUtteranceActive.withLock { $0 = true }
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        streamRelay.bind(continuation)
        return stream
    }

    /// Stop forwarding buffers; finishes the ASR stream.
    public func endUtterance() {
        isUtteranceActive.withLock { $0 = false }
        streamRelay.finish()
    }

    public func cancelUtterance() {
        endUtterance()
    }

    public func currentAudioLevels() -> [Float] {
        levelStore.snapshot()
    }

    // MARK: - Audio tap (nonisolated — runs on realtime thread)

    private nonisolated static func makeAudioTapBlock(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        hwFormat: AVAudioFormat,
        utteranceFlag: OSAllocatedUnfairLock<Bool>,
        levelStore: FlowLevelStore,
        streamRelay: FlowCaptureStreamRelay
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            levelStore.update(from: buffer, barCount: FlowCaptureConstants.levelBarCount)

            guard utteranceFlag.withLock({ $0 }) else { return }

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
            streamRelay.yield(snapshot)
        }
    }
}
