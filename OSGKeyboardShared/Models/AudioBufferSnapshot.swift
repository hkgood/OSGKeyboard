// AudioBufferSnapshot.swift
// OSGKeyboard · Shared
//
// Sendable wrapper around a Float32 audio buffer's raw samples.
// The snapshot is the only thing that crosses actor / concurrency
// boundaries; the recognizer re-creates an `AVAudioPCMBuffer` on its
// own side and consumes it locally (never yielding it back out).

import Foundation
import AVFoundation

public struct AudioBufferSnapshot: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    /// Construct from an `AVAudioPCMBuffer` by copying out the channel data.
    public init(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else {
            self.samples = []
            self.sampleRate = buffer.format.sampleRate
            return
        }
        let n = Int(buffer.frameLength)
        var copy = [Float](repeating: 0, count: n)
        memcpy(&copy, channelData[0], n * MemoryLayout<Float>.size)
        self.samples = copy
        self.sampleRate = buffer.format.sampleRate
    }
}
