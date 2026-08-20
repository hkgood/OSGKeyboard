// UtteranceBatchFallbackPolicy.swift
// OSGKeyboard · Shared
//
// Decides when to re-run ASR on the full utterance PCM after pipelined
// chunking, and how to pick the best transcript among candidates.

import Foundation

public enum UtteranceBatchFallbackPolicy {
    public static let defaultCharacterAdvantage = UtteranceTranscriptGuard.defaultPartialAdvantage

    /// True when chunked output likely lost trailing content vs the live partial.
    public static func shouldRunBatchFallback(
        stitchedFinal: String,
        partialSnapshot: String,
        recognitionFailed: Bool = false,
        minimumCharacterAdvantage: Int = defaultCharacterAdvantage
    ) -> Bool {
        if recognitionFailed { return true }
        let final = stitchedFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = partialSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)

        if final.isEmpty, !partial.isEmpty { return true }
        if partial.isEmpty { return false }
        return partial.count >= final.count + minimumCharacterAdvantage
    }

    /// Prefer the longest non-empty transcript after batch ASR completes.
    public static func preferredTranscript(
        batch: String,
        stitchedFinal: String,
        partialSnapshot: String,
        current: String
    ) -> String {
        let candidates = [batch, current, stitchedFinal, partialSnapshot]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let best = candidates.max(by: { $0.count < $1.count }) else {
            return current.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return best
    }
}
