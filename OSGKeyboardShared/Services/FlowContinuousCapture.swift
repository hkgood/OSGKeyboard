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
    private let isUtteranceActive = OSAllocatedUnfairLock(initialState: false)

    private var didInstallTap = false
    private var isRunning = false

    private var routeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private let log = Logger(subsystem: "com.osgkeyboard.shared", category: "FlowCapture")

    public init() {}

    public var running: Bool { isRunning }

    /// Configure `.playAndRecord`, install a permanent input tap, start the engine.
    public func start() throws {
        guard !isRunning else { return }
        try activateEngine()
        isRunning = true
        installSessionObservers()
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

        // Rebuild the tap so its bound hardware format matches the new route.
        if didInstallTap {
            inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        let tap = Self.makeAudioTapBlock(
            converter: converter,
            targetFormat: targetFormat,
            hwFormat: hwFormat,
            utteranceFlag: isUtteranceActive,
            levelStore: levelStore,
            prerollStore: prerollStore,
            streamRelay: streamRelay
        )
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat, block: tap)
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

    // MARK: - Route / interruption recovery

    private func installSessionObservers() {
        let center = NotificationCenter.default
        if routeObserver == nil {
            routeObserver = center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                // Extract Sendable primitives here (Notification isn't Sendable)
                // before hopping onto the main actor.
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
    }

    private func removeSessionObservers() {
        let center = NotificationCenter.default
        if let routeObserver { center.removeObserver(routeObserver) }
        if let interruptionObserver { center.removeObserver(interruptionObserver) }
        routeObserver = nil
        interruptionObserver = nil
    }

    private func handleRouteChange(reasonRaw: UInt?) {
        guard isRunning else { return }
        guard let reasonRaw,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw) else { return }
        // Only rebuild for real device swaps (plugging / unplugging a headset
        // or AirPods). Ignore `.categoryChange`, which we trigger ourselves.
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
            // The system already paused our engine; wait for `.ended`.
            log.info("Audio interruption began")
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
        guard isRunning else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        do {
            try activateEngine()
        } catch {
            log.error("Engine rebuild failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Begin forwarding downsampled buffers to ASR for one utterance.
    public func beginUtterance() -> AsyncStream<AudioBufferSnapshot> {
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        // Bind the consumer before opening the gate so early tap frames
        // are not dropped on the floor.
        streamRelay.bind(continuation)
        streamRelay.replay(prerollStore.drain())
        isUtteranceActive.withLock { $0 = true }
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
        prerollStore: FlowPrerollStore,
        streamRelay: FlowCaptureStreamRelay
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

            if utteranceFlag.withLock({ $0 }) {
                streamRelay.yield(snapshot)
            } else {
                prerollStore.append(snapshot)
            }
        }
    }
}
