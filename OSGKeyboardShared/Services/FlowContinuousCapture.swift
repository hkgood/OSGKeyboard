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
    private let gate = OSAllocatedUnfairLock(initialState: UtteranceGatePhase.idle)
    private let drainTracker = FlowCaptureDrainTracker()
    private let tailSampleCounter = OSAllocatedUnfairLock(initialState: 0)

    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var hwFormat: AVAudioFormat?
    private var drainPolicy = FlowCaptureTailDrainPolicy.flowDefault

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
        guard let converter = AVAudioConverter(from: hardwareFormat, to: resolvedTargetFormat) else {
            throw StartError.converterCreateFailed
        }

        audioConverter = converter
        targetFormat = resolvedTargetFormat
        hwFormat = hardwareFormat

        if !didInstallTap {
            let gateLock = gate
            let relay = streamRelay
            let preroll = prerollStore
            let levels = levelStore
            let tracker = drainTracker
            let tailCounter = tailSampleCounter
            let policy = drainPolicy
            let tap = Self.makeAudioTapBlock(
                converter: converter,
                targetFormat: resolvedTargetFormat,
                hwFormat: hardwareFormat,
                gate: gateLock,
                levelStore: levels,
                prerollStore: preroll,
                streamRelay: relay,
                drainTracker: tracker,
                tailSampleCounter: tailCounter,
                drainPolicy: policy
            )
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat, block: tap)
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
        audioConverter = nil
        targetFormat = nil
        hwFormat = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    /// Re-activate capture after returning from background without
    /// reinstalling the tap (iOS may deactivate the audio session).
    public func reassertIfRunning() {
        guard isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
        )
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
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

        let flushSamples = flushConverterTailToStream()
        tailSampleCounter.withLock { $0 += flushSamples }

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

    // MARK: - Converter flush

    @discardableResult
    private func flushConverterTailToStream() -> Int {
        guard let converter = audioConverter,
              let targetFormat,
              let hwFormat else {
            return 0
        }

        var flushedSamples = 0
        let capacity = AVAudioFrameCount(max(512, hwFormat.sampleRate / 20))
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return 0
        }

        var endOfStreamSignaled = false
        while true {
            outBuffer.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                if endOfStreamSignaled {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                endOfStreamSignaled = true
                outStatus.pointee = .endOfStream
                return nil
            }

            if status == .error || error != nil {
                break
            }
            guard status == .haveData, outBuffer.frameLength > 0 else {
                break
            }

            let snapshot = AudioBufferSnapshot(buffer: outBuffer)
            guard !snapshot.samples.isEmpty else { break }
            streamRelay.yield(snapshot)
            flushedSamples += snapshot.samples.count
        }

        return flushedSamples
    }

    // MARK: - Audio tap (nonisolated — runs on realtime thread)

    private nonisolated static func makeAudioTapBlock(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        hwFormat: AVAudioFormat,
        gate: OSAllocatedUnfairLock<UtteranceGatePhase>,
        levelStore: FlowLevelStore,
        prerollStore: FlowPrerollStore,
        streamRelay: FlowCaptureStreamRelay,
        drainTracker: FlowCaptureDrainTracker,
        tailSampleCounter: OSAllocatedUnfairLock<Int>,
        drainPolicy: FlowCaptureTailDrainPolicy
    ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        return { buffer, _ in
            levelStore.update(from: buffer, barCount: FlowCaptureConstants.levelBarCount)

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
