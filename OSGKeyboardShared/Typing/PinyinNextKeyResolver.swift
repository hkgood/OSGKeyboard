// PinyinNextKeyResolver.swift
// OSGKeyboard · Shared
//
// Phase 4: legal next letters during full-pinyin composition.
// Double-pinyin schemas return nil (no bias) until a dedicated FSM exists.

import CoreGraphics
import Foundation

public enum KeyHitBiasMetrics: Sendable {
    /// Legal next letters are slightly “sticky” in ambiguous hit tests.
    public static let legalBoost: CGFloat = 1.20
    /// Illegal letters shrink a little but remain reachable.
    public static let illegalShrink: CGFloat = 0.90
    public static let neutral: CGFloat = 1.0
}

public enum PinyinNextKeyResolver {
    /// Returns legal next key characters, or `nil` when bias should be off.
    public static func validNextKeys(
        rawInput: String,
        schema: TypingInputSchema,
        language: TypingInputLanguage,
        page: TypingKeyPage
    ) -> Set<Character>? {
        guard language == .chinese, page == .letters else { return nil }
        // Phase 4a: full pinyin only. Double-pinyin stays neutral.
        guard schema == .fullPinyin else { return nil }

        let normalized = normalize(rawInput)
        guard !normalized.isEmpty else { return nil }

        let segment = lastSpellingSegment(normalized)
        var result = Set<Character>()
        collectNext(prefix: segment, into: &result)
        return result.isEmpty ? nil : result
    }

    /// Maps layout keys → hit weights for ambiguous nearest-key resolution.
    public static func hitWeights(
        for keys: [TypingKeyHitTarget],
        validNext: Set<Character>?
    ) -> [String: CGFloat] {
        guard let validNext, !validNext.isEmpty else { return [:] }

        var weights: [String: CGFloat] = [:]
        for key in keys {
            guard key.id.hasPrefix("grid.") else { continue }
            guard key.behavior == .commitOnRelease else { continue }
            let label = key.label.lowercased()
            guard label.count == 1, let char = label.first, char.isLetter else {
                continue
            }
            weights[key.id] = validNext.contains(char)
                ? KeyHitBiasMetrics.legalBoost
                : KeyHitBiasMetrics.illegalShrink
        }
        return weights
    }

    // MARK: - Internals

    private static func normalize(_ raw: String) -> String {
        raw.lowercased().replacingOccurrences(of: "ü", with: "v")
    }

    private static func lastSpellingSegment(_ input: String) -> String {
        let lettersAndDelim = input.filter { $0.isLetter || $0 == "'" || $0 == " " }
        let parts = lettersAndDelim.split { $0 == "'" || $0 == " " }
        return parts.last.map(String.init) ?? ""
    }

    private static func collectNext(prefix: String, into result: inout Set<Character>) {
        var canExtend = false
        for syllable in PinyinSyllableTable.syllables
            where syllable.hasPrefix(prefix) && syllable.count > prefix.count {
            let index = syllable.index(syllable.startIndex, offsetBy: prefix.count)
            result.insert(syllable[index])
            canExtend = true
        }

        // Complete syllable (or empty) → also allow starting a new syllable.
        if prefix.isEmpty || PinyinSyllableTable.syllables.contains(prefix) {
            for syllable in PinyinSyllableTable.syllables {
                if let first = syllable.first {
                    result.insert(first)
                }
            }
        }

        // Multi-syllable undelimited input (e.g. "zhongg" → "zhong" + "g").
        // Only peel when the whole prefix cannot extend as one syllable.
        if !canExtend, !prefix.isEmpty {
            let longest = PinyinSyllableTable.longestSyllablePrefix(of: prefix)
            if !longest.isEmpty, longest.count < prefix.count {
                let remainder = String(prefix.dropFirst(longest.count))
                collectNext(prefix: remainder, into: &result)
            }
        }
    }
}
