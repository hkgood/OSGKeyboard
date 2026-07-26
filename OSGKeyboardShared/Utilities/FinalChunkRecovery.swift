// FinalChunkRecovery.swift
// OSGKeyboard · Shared
//
// Recovery plans for pipelined utterance ASR when the final chunk is short,
// empty, or straddles a chunk boundary.

import Foundation

public enum FinalChunkRecovery {

    /// Samples and stitch index when the final chunk should be merged with
    /// prior overlap *before* the first ASR pass.
    public static func preMergePlan(
        chunk: UtteranceAudioChunk,
        processedChunks: Int,
        previousChunkSamples: [Float],
        config: FlowUtteranceChunkConfig
    ) -> (samples: [Float], stitchIndex: Int)? {
        guard chunk.isLast, !chunk.samples.isEmpty, !previousChunkSamples.isEmpty else {
            return nil
        }
        guard chunk.samples.count < config.minFinalChunkSamples else { return nil }

        let merged = Array(previousChunkSamples.suffix(config.overlapSamples)) + chunk.samples
        return (merged, max(0, chunk.index - 1))
    }

    /// Retry plan when the final chunk had audio but ASR returned empty text.
    public static func emptyResultRetryPlan(
        chunk: UtteranceAudioChunk,
        previousChunkSamples: [Float],
        config: FlowUtteranceChunkConfig,
        asrText: String
    ) -> (samples: [Float], stitchIndex: Int)? {
        guard chunk.isLast, !chunk.samples.isEmpty else { return nil }
        guard asrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if previousChunkSamples.isEmpty {
            return (chunk.samples, chunk.index)
        }

        let merged = Array(previousChunkSamples.suffix(config.overlapSamples)) + chunk.samples
        return (merged, max(0, chunk.index - 1))
    }
}
