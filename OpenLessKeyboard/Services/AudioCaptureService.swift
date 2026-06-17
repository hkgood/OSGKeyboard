// AudioCaptureService.swift
// OSGKeyboard · Keyboard Extension
//
// Captures microphone audio at 16 kHz mono Float32 using AVAudioEngine.
// Exposes an AsyncStream<AVAudioPCMBuffer> that ASR services can consume.

import Foundation
@preconcurrency import AVFoundation

public actor AudioCaptureService {

    public enum CaptureError: Error {
        case sessionConfigFailed(Error)
        case engineStartFailed(Error)
        case noInputNode
    }

    private let engine = AVAudioEngine()
    private let converter = AVAudioConverter(
        from: AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!,
        to: AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
    )

    private var continuation: AsyncStream<AudioBufferSnapshot>.Continuation?
    private var isRunning = false

    public init() {}

    public func start() -> AsyncStream<AudioBufferSnapshot> {
        AsyncStream { continuation in
            self.continuation = continuation
            do {
                try configureSession()
                try attachTap()
                try engine.start()
                isRunning = true
            } catch {
                continuation.finish()
                self.continuation = nil
                isRunning = false
            }
        }
    }

    public func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
        isRunning = false
    }

    private func configureSession() throws {
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw CaptureError.sessionConfigFailed(error)
        }
        #endif
    }

    private func attachTap() throws {
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0 else {
            throw CaptureError.noInputNode
        }
        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }
            // Downsample to 16 kHz mono Float32
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )!
            let outFrames = AVAudioFrameCount(
                Double(buffer.frameLength) * 16_000.0 / hardwareFormat.sampleRate
            )
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else {
                return
            }
            var error: NSError?
            let status = self.converter?.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .haveData, error == nil {
                // AVAudioPCMBuffer is not Sendable; copy the raw float data
                // into a Sendable wrapper so we can hand it to the actor.
                let copy = AudioBufferSnapshot(buffer: outBuffer)
                Task { await self.deliver(copy) }
            }
        }
    }

    private func deliver(_ snapshot: AudioBufferSnapshot) {
        guard isRunning else { return }
        continuation?.yield(snapshot)
    }
}

/// Sendable wrapper around a Float32 audio buffer's raw samples.
/// We re-decode on the consumer side to avoid AVAudioPCMBuffer's non-Sendable
/// type crossing the actor boundary.
public struct AudioBufferSnapshot: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            self.samples = []
            self.sampleRate = 16_000
            return
        }
        let n = Int(buffer.frameLength)
        var copy = [Float](repeating: 0, count: n)
        memcpy(&copy, channelData[0], n * MemoryLayout<Float>.size)
        self.samples = copy
        self.sampleRate = buffer.format.sampleRate
    }
}

public extension AsyncStream where Element == AudioBufferSnapshot {
    /// Convenience: convert snapshots to AVAudioPCMBuffer 16kHz mono Float32.
    func toAVAudioBuffers() -> AsyncStream<AVAudioPCMBuffer> {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        let snapshots = self
        return AsyncStream<AVAudioPCMBuffer> { continuation in
            Task {
                for await snap in snapshots {
                    guard !snap.samples.isEmpty,
                          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(snap.samples.count))
                    else { continue }
                    pcm.frameLength = AVAudioFrameCount(snap.samples.count)
                    if let dst = pcm.floatChannelData?[0] {
                        snap.samples.withUnsafeBufferPointer { src in
                            if let base = src.baseAddress {
                                memcpy(dst, base, snap.samples.count * MemoryLayout<Float>.size)
                            }
                        }
                    }
                    continuation.yield(pcm)
                }
                continuation.finish()
            }
        }
    }
}
