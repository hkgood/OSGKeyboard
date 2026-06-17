// AudioCaptureService.swift
// OSGKeyboard · Keyboard Extension
//
// Captures microphone audio at 16 kHz mono Float32 using AVAudioEngine.
// Designed for use inside an iOS Custom Keyboard Extension:
//   • Uses `.record` (not `.playAndRecord`) — keyboards cannot play.
//   • Exposes a Sendable `Session` with two streams:
//       - `audio`: 16 kHz mono Float32 frames for ASR.
//       - `levels`: RMS + peak dBFS for the animated waveform.
//   • All mutable state is guarded by a lock; class is `@unchecked Sendable`
//     for use with Swift 6 strict concurrency.

import Foundation
import AVFoundation
import os.lock
import OSGKeyboardShared

// MARK: - Sendable conformance
//
// `AVAudioEngine` is not Sendable, but the iOS audio APIs hand us
// closures that need to capture it. We never mutate the engine
// concurrently — capture / conversion are serialised on the actor, and
// the tap closure only reads pointers into it. So an unchecked
// retroactive Sendable conformance is sound here.
// `AVAudioConverter` and `AVAudioFormat` are already Sendable in newer
// SDKs; we don't need to redeclare.
extension AVAudioEngine: @unchecked @retroactive Sendable {}

public final class AudioCaptureService: @unchecked Sendable {

    // MARK: - Errors

    public enum CaptureError: LocalizedError, Sendable {
        case sessionConfigFailed(String)
        case engineStartFailed(String)
        case noInputNode
        case alreadyRunning

        public var errorDescription: String? {
            switch self {
            case .sessionConfigFailed(let s): return "Audio session config failed: \(s)"
            case .engineStartFailed(let s):    return "Audio engine failed to start: \(s)"
            case .noInputNode:                 return "No microphone input available."
            case .alreadyRunning:              return "Audio capture is already running."
            }
        }
    }

    // MARK: - Level payload (Sendable)

    public struct Level: Sendable, Equatable {
        /// Root-mean-square, 0...1 (linear).
        public let rms: Float
        /// Peak amplitude, 0...1 (linear).
        public let peak: Float
        public let timestamp: TimeInterval

        /// Convenience: -20 dBFS … 0 dBFS mapped to 0…1 for UI meters.
        public var meter: Float {
            // Clamp floor at -50 dB so silence still shows a tiny bar.
            let db = 20 * log10(max(rms, 1e-7))
            let clamped = max(-50, min(0, db))
            return Float((clamped + 50) / 50)
        }
    }

    // MARK: - Session (one capture run)

    /// A single capture run. Two streams + a stop handle.
    public final class Session: @unchecked Sendable {
        public let audio: AsyncStream<AudioBufferSnapshot>
        public let levels: AsyncStream<Level>
        private let onStop: @Sendable () -> Void

        fileprivate init(
            audio: AsyncStream<AudioBufferSnapshot>,
            levels: AsyncStream<Level>,
            onStop: @escaping @Sendable () -> Void
        ) {
            self.audio = audio
            self.levels = levels
            self.onStop = onStop
        }

        public func stop() { onStop() }
    }

    // MARK: - State

    private let lock = OSAllocatedUnfairLock()
    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var audioContinuation: AsyncStream<AudioBufferSnapshot>.Continuation?
    private var levelContinuation: AsyncStream<Level>.Continuation?
    private var isRunning: Bool = false

    public init() {}

    deinit { stopInternal() }

    // MARK: - Public API

    /// Start capture. Returns a `Session` whose streams yield audio + level data.
    /// The session ends when `Session.stop()` is called or the extension is torn down.
    @discardableResult
    public func start() -> Session {
        let (audioStream, audioCont) = AsyncStream<AudioBufferSnapshot>.makeStream()
        let (levelStream, levelCont) = AsyncStream<Level>.makeStream()

        // Fail fast if already running.
        let alreadyRunning: Bool = lock.withLock { isRunning }
        if alreadyRunning {
            audioCont.finish()
            levelCont.finish()
            return Session(audio: audioStream, levels: levelStream, onStop: {})
        }

        do {
            try configureSession()
            try bootstrap(audioCont: audioCont, levelCont: levelCont)
            lock.withLock {
                isRunning = true
                audioContinuation = audioCont
                levelContinuation = levelCont
            }
        } catch {
            // Tear down whatever we partially created.
            audioCont.finish()
            levelCont.finish()
            teardownEngine()
            return Session(audio: audioStream, levels: levelStream, onStop: {})
        }

        return Session(
            audio: audioStream,
            levels: levelStream,
            onStop: { [weak self] in self?.stop() }
        )
    }

    public func stop() {
        stopInternal()
    }

    // MARK: - Setup

    private func configureSession() throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            // `.record` — keyboards cannot play audio, so .playAndRecord is wrong.
            // `.measurement` mode disables system AGC/echo cancellation for cleaner ASR input.
            // `.duckOthers` is harmless in record-only.
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw CaptureError.sessionConfigFailed(error.localizedDescription)
        }
        #endif
    }

    private func bootstrap(
        audioCont: AsyncStream<AudioBufferSnapshot>.Continuation,
        levelCont: AsyncStream<Level>.Continuation
    ) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw CaptureError.noInputNode
        }

        let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: hardwareFormat, to: target) else {
            throw CaptureError.engineStartFailed("converter init failed")
        }

        // Persistent buffer for level computation: we re-use Float arrays to
        // avoid per-tap allocations.
        let levelScratch = LevelScratch()

        input.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, when in
            // We capture self weakly only to keep the AudioCaptureService
            // alive while the tap is installed; the tap itself only
            // touches the local `audioCont` / `levelCont` continuations.
            guard self != nil else { return }
            // 1) Compute level from raw hardware buffer (preserves true amplitude).
            let (rms, peak) = levelScratch.measure(buffer: buffer)
            // `AVAudioTime` carries both `sampleTime` (frames on the device
            // clock) and `hostTime` (mach absolute time). We only need a
            // monotonically increasing source for the timestamp; sample
            // time / sample rate is good enough and is independent of the
            // host clock.
            let ts: Double
            if when.sampleTime > 0, hardwareFormat.sampleRate > 0 {
                ts = Double(when.sampleTime) / hardwareFormat.sampleRate
            } else {
                ts = Date().timeIntervalSinceReferenceDate
            }
            levelCont.yield(Level(rms: rms, peak: peak, timestamp: ts))

            // 2) Convert to 16 kHz mono Float32 for ASR.
            let outFrames = AVAudioFrameCount(
                Double(buffer.frameLength) * 16_000.0 / hardwareFormat.sampleRate
            )
            guard outFrames > 0,
                  let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames)
            else { return }

            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .haveData, error == nil {
                let snap = AudioBufferSnapshot(buffer: outBuffer)
                audioCont.yield(snap)
            }
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.engineStartFailed(error.localizedDescription)
        }

        lock.withLock {
            self.engine = engine
            self.converter = converter
        }
    }

    // MARK: - Teardown

    private func stopInternal() {
        let (wasRunning, engine, audioCont, levelCont) = lock.withLock { () -> (Bool, AVAudioEngine?, AsyncStream<AudioBufferSnapshot>.Continuation?, AsyncStream<Level>.Continuation?) in
            let was = isRunning
            isRunning = false
            let eng = self.engine
            let ac = audioContinuation
            let lc = levelContinuation
            self.engine = nil
            self.converter = nil
            self.audioContinuation = nil
            self.levelContinuation = nil
            return (was, eng, ac, lc)
        }
        guard wasRunning else { return }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        #if canImport(UIKit)
        // Deactivate the session so other apps' audio routing is restored.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
        audioCont?.finish()
        levelCont?.finish()
    }

    private func teardownEngine() {
        let (engine, audioCont, levelCont) = lock.withLock { () -> (AVAudioEngine?, AsyncStream<AudioBufferSnapshot>.Continuation?, AsyncStream<Level>.Continuation?) in
            let e = self.engine
            let a = audioContinuation
            let l = levelContinuation
            self.engine = nil
            self.converter = nil
            self.audioContinuation = nil
            self.levelContinuation = nil
            self.isRunning = false
            return (e, a, l)
        }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        audioCont?.finish()
        levelCont?.finish()
    }
}

// MARK: - Level scratch (lock-free, single-writer / single-reader per tap)

/// Lock-free per-tap scratch for RMS + peak measurement. The AVAudio tap is
/// always invoked serially per input node, so we don't need a lock here.
private final class LevelScratch: @unchecked Sendable {
    private var last: (rms: Float, peak: Float) = (0, 0)

    func measure(buffer: AVAudioPCMBuffer) -> (rms: Float, peak: Float) {
        guard let ch = buffer.floatChannelData?[0] else { return last }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return last }

        // Decay smoothing — keeps the meter lively but not jittery.
        var sumSq: Float = 0
        var peak: Float = 0
        for i in 0..<n {
            let s = ch[i]
            sumSq += s * s
            let a = abs(s)
            if a > peak { peak = a }
        }
        let rms = sqrtf(sumSq / Float(n))

        // Exponential moving average for visual smoothness.
        let alpha: Float = 0.35
        let smoothedRms = alpha * rms + (1 - alpha) * last.rms
        let smoothedPeak = max(alpha * peak, (1 - alpha) * last.peak)
        last = (smoothedRms, smoothedPeak)
        return (smoothedRms, smoothedPeak)
    }
}
