// UtteranceTranscriptGuard.swift
// OSGKeyboard · Shared
//
// Chooses the best available transcript when pipelined final text may have
// dropped a weak tail segment.

import Foundation

public enum UtteranceTranscriptGuard {
    /// Partial must exceed final by at least this many characters to win.
    public static let defaultPartialAdvantage = 8

    /// Prefer `stitchedFinal` unless empty or clearly shorter than the live
    /// partial snapshot taken at mic stop.
    public static func resolve(
        stitchedFinal: String,
        partialSnapshot: String,
        minimumPartialAdvantage: Int = defaultPartialAdvantage
    ) -> String {
        let final = stitchedFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = partialSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)

        if final.isEmpty { return partial }
        if partial.isEmpty { return final }

        if partial.count >= final.count + minimumPartialAdvantage {
            FlowPipelineDiagnostics.logTranscriptGuardUsedPartial(
                finalLength: final.count,
                partialLength: partial.count
            )
            return partial
        }
        return final
    }
}
