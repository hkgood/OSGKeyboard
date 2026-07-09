// LocalASRTranscriptCorrector.swift
// OSGKeyboard · Shared
//
// Deterministic alias → canonical term replacement between raw ASR output
// and the LLM polish step. Only applies whole-phrase matches.

import Foundation

public enum LocalASRTranscriptCorrector {

    /// Applies high-confidence alias replacements (longest match first).
    public static func apply(
        _ text: String,
        pairs: [LocalASRCorrectionPair]
    ) -> String {
        guard !text.isEmpty, !pairs.isEmpty else { return text }

        let sorted = pairs.sorted { lhs, rhs in
            if lhs.alias.count != rhs.alias.count {
                return lhs.alias.count > rhs.alias.count
            }
            return lhs.alias.localizedCaseInsensitiveCompare(rhs.alias) == .orderedAscending
        }

        var result = text
        for pair in sorted {
            result = replaceWholeMatches(
                in: result,
                alias: pair.alias,
                term: pair.term
            )
        }
        return result
    }

    // MARK: - Private

    private static func replaceWholeMatches(
        in text: String,
        alias: String,
        term: String
    ) -> String {
        guard !alias.isEmpty, alias != term else { return text }

        if alias.unicodeScalars.allSatisfy({ $0.isASCII }) {
            return replaceASCIIWord(in: text, alias: alias, term: term)
        }
        return text.replacingOccurrences(of: alias, with: term)
    }

    private static func replaceASCIIWord(
        in text: String,
        alias: String,
        term: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: alias)
        let pattern = "(?i)(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: term
        )
    }
}
