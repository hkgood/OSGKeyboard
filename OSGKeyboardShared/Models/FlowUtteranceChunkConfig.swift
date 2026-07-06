// FlowUtteranceChunkConfig.swift
// OSGKeyboard · Shared
//
// Chunking policy for pipelined Flow utterance ASR (up to 3.5 minutes).

import Foundation

public struct FlowUtteranceChunkConfig: Sendable, Equatable {
    /// Target duration for the first ASR chunk (starts pipelining early).
    public let firstChunkDurationSeconds: TimeInterval
    /// Target duration for later chunks once pipelining is underway.
    public let subsequentChunkDurationSeconds: TimeInterval
    /// Tail overlap fed into the next chunk for boundary dedup when stitching.
    public let overlapDurationSeconds: TimeInterval
    /// After hitting the max window, wait up to this long for a pause before hard-splitting.
    public let pauseExtensionMaxSeconds: TimeInterval
    /// RMS below this is treated as a pause candidate (Float32 mono @ 16 kHz).
    public let pauseRMSThreshold: Float
    /// Final chunk shorter than this is re-transcribed merged with the prior tail overlap.
    public let minFinalChunkDurationSeconds: TimeInterval
    public let sampleRate: Int

    public init(
        firstChunkDurationSeconds: TimeInterval = 2.5,
        subsequentChunkDurationSeconds: TimeInterval = 5.0,
        overlapDurationSeconds: TimeInterval,
        pauseExtensionMaxSeconds: TimeInterval,
        pauseRMSThreshold: Float,
        minFinalChunkDurationSeconds: TimeInterval = 0.8,
        sampleRate: Int
    ) {
        self.firstChunkDurationSeconds = firstChunkDurationSeconds
        self.subsequentChunkDurationSeconds = subsequentChunkDurationSeconds
        self.overlapDurationSeconds = overlapDurationSeconds
        self.pauseExtensionMaxSeconds = pauseExtensionMaxSeconds
        self.pauseRMSThreshold = pauseRMSThreshold
        self.minFinalChunkDurationSeconds = minFinalChunkDurationSeconds
        self.sampleRate = sampleRate
    }

    /// Uniform chunk size — used by unit tests and legacy call sites.
    public init(
        maxChunkDurationSeconds: TimeInterval,
        overlapDurationSeconds: TimeInterval,
        pauseExtensionMaxSeconds: TimeInterval,
        pauseRMSThreshold: Float,
        minFinalChunkDurationSeconds: TimeInterval = 0.8,
        sampleRate: Int
    ) {
        self.firstChunkDurationSeconds = maxChunkDurationSeconds
        self.subsequentChunkDurationSeconds = maxChunkDurationSeconds
        self.overlapDurationSeconds = overlapDurationSeconds
        self.pauseExtensionMaxSeconds = pauseExtensionMaxSeconds
        self.pauseRMSThreshold = pauseRMSThreshold
        self.minFinalChunkDurationSeconds = minFinalChunkDurationSeconds
        self.sampleRate = sampleRate
    }

    /// Backward-compatible alias for tests that read `maxChunkSamples`.
    public var maxChunkDurationSeconds: TimeInterval {
        subsequentChunkDurationSeconds
    }

    public func maxChunkDurationSeconds(forChunkIndex index: Int) -> TimeInterval {
        index == 0 ? firstChunkDurationSeconds : subsequentChunkDurationSeconds
    }

    public func maxChunkSamples(forChunkIndex index: Int) -> Int {
        Int(maxChunkDurationSeconds(forChunkIndex: index) * Double(sampleRate))
    }

    public var maxChunkSamples: Int {
        maxChunkSamples(forChunkIndex: 1)
    }

    public var overlapSamples: Int {
        Int(overlapDurationSeconds * Double(sampleRate))
    }

    public var pauseExtensionSamples: Int {
        Int(pauseExtensionMaxSeconds * Double(sampleRate))
    }

    public var minFinalChunkSamples: Int {
        Int(minFinalChunkDurationSeconds * Double(sampleRate))
    }

    /// Default for keyboard Flow utterances (≤ 3 min, pipelined ASR).
    public static let flowDefault = FlowUtteranceChunkConfig(
        firstChunkDurationSeconds: 2.5,
        subsequentChunkDurationSeconds: 5.0,
        overlapDurationSeconds: 0.5,
        pauseExtensionMaxSeconds: 2,
        pauseRMSThreshold: 0.015,
        minFinalChunkDurationSeconds: 0.8,
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
