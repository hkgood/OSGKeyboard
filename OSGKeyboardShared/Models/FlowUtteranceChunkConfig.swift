// FlowUtteranceChunkConfig.swift
// OSGKeyboard · Shared
//
// Chunking policy for pipelined Flow utterance ASR (up to 3 minutes).

import Foundation

public struct FlowUtteranceChunkConfig: Sendable, Equatable {
    /// Target maximum duration per ASR chunk.
    public let maxChunkDurationSeconds: TimeInterval
    /// Tail overlap fed into the next chunk for boundary dedup when stitching.
    public let overlapDurationSeconds: TimeInterval
    /// After hitting the max window, wait up to this long for a pause before hard-splitting.
    public let pauseExtensionMaxSeconds: TimeInterval
    /// RMS below this is treated as a pause candidate (Float32 mono @ 16 kHz).
    public let pauseRMSThreshold: Float
    public let sampleRate: Int

    public init(
        maxChunkDurationSeconds: TimeInterval,
        overlapDurationSeconds: TimeInterval,
        pauseExtensionMaxSeconds: TimeInterval,
        pauseRMSThreshold: Float,
        sampleRate: Int
    ) {
        self.maxChunkDurationSeconds = maxChunkDurationSeconds
        self.overlapDurationSeconds = overlapDurationSeconds
        self.pauseExtensionMaxSeconds = pauseExtensionMaxSeconds
        self.pauseRMSThreshold = pauseRMSThreshold
        self.sampleRate = sampleRate
    }

    public var maxChunkSamples: Int {
        Int(maxChunkDurationSeconds * Double(sampleRate))
    }

    public var overlapSamples: Int {
        Int(overlapDurationSeconds * Double(sampleRate))
    }

    public var pauseExtensionSamples: Int {
        Int(pauseExtensionMaxSeconds * Double(sampleRate))
    }

    /// Default for keyboard Flow utterances (≤ 3 min, pipelined ASR).
    public static let flowDefault = FlowUtteranceChunkConfig(
        maxChunkDurationSeconds: 30,
        overlapDurationSeconds: 0.5,
        pauseExtensionMaxSeconds: 2,
        pauseRMSThreshold: 0.015,
        sampleRate: 16_000
    )
}

public struct UtteranceAudioChunk: Sendable, Equatable {
    public let index: Int
    public let samples: [Float]
    public let isLast: Bool

    public init(index: Int, samples: [Float], isLast: Bool) {
        self.index = index
        self.samples = samples
        self.isLast = isLast
    }

    public var durationSeconds: Double {
        Double(samples.count) / 16_000.0
    }
}
