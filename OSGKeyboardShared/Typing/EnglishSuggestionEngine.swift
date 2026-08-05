// EnglishSuggestionEngine.swift
// OSGKeyboard · Shared
//
// Builds TypingComposition for English: completions while composing,
// high-confidence corrections on commit, next-word predictions after.

import Foundation

public struct EnglishSuggestionContext: Sendable {
    public var currentWord: String
    public var previousWord: String
    public var personalTerms: [String]
    public var learnedBoosts: [String: Int]
    public var includeOriginalAfterCorrection: String?

    public init(
        currentWord: String = "",
        previousWord: String = "",
        personalTerms: [String] = [],
        learnedBoosts: [String: Int] = [:],
        includeOriginalAfterCorrection: String? = nil
    ) {
        self.currentWord = currentWord
        self.previousWord = previousWord
        self.personalTerms = personalTerms
        self.learnedBoosts = learnedBoosts
        self.includeOriginalAfterCorrection = includeOriginalAfterCorrection
    }
}

public struct EnglishCorrectionDecision: Equatable, Sendable {
    public var original: String
    public var replacement: String
    /// Trailing characters inserted with the replacement (`" "`, `"\n"`, punct).
    public var appliedSuffix: String

    public init(original: String, replacement: String, appliedSuffix: String = "") {
        self.original = original
        self.replacement = replacement
        self.appliedSuffix = appliedSuffix
    }

    public var undoDeleteCount: Int {
        replacement.count + appliedSuffix.count
    }
}

/// Pure ranking / candidate builder — no UITextDocumentProxy access.
public struct EnglishSuggestionEngine: Sendable {
    private let lexicon: EnglishLexicon

    public init(lexicon: EnglishLexicon = .shared) {
        self.lexicon = lexicon
    }

    public func prepare() {
        lexicon.prepare()
    }

    /// Suggestions while the user is mid-word.
    public func compositionWhileTyping(_ context: EnglishSuggestionContext) -> TypingComposition {
        let prefix = context.currentWord
        guard !prefix.isEmpty else {
            return nextWordComposition(context)
        }

        var ranked: [(text: String, score: Int, id: String)] = []
        var seen = Set<String>()

        func append(_ raw: String, baseScore: Int, tag: String, preserveCase: Bool = false) {
            let display = preserveCase ? raw : matchCase(of: prefix, to: raw)
            let key = display.lowercased()
            guard seen.insert(key).inserted else { return }
            let boost = context.learnedBoosts[key] ?? 0
            let personalBoost = context.personalTerms.contains { $0.lowercased() == key } ? 5_000 : 0
            ranked.append((display, baseScore + boost + personalBoost, "\(tag)|\(key)"))
        }

        for term in context.personalTerms where term.lowercased().hasPrefix(prefix.lowercased())
            && term.lowercased() != prefix.lowercased() {
            append(term, baseScore: 8_000 + term.count, tag: "personal", preserveCase: true)
        }

        for word in lexicon.completions(prefix: prefix, limit: 12) {
            append(word, baseScore: lexicon.frequency(of: word), tag: "complete")
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.text.count < rhs.text.count
        }

        let candidates = ranked.prefix(8).map {
            TypingCandidate(id: $0.id, text: $0.text, engineIndex: 0)
        }
        return TypingComposition(preedit: prefix, candidates: Array(candidates))
    }

    /// Decide whether to autocorrect on space / punctuation.
    public func correctionDecision(
        for typed: String,
        personalTerms: [String],
        learnedBoosts: [String: Int]
    ) -> EnglishCorrectionDecision? {
        let trimmed = typed
        guard trimmed.count >= 2 else { return nil }
        let lower = trimmed.lowercased()

        if personalTerms.contains(where: { $0.lowercased() == lower }) { return nil }
        if (learnedBoosts[lower] ?? 0) >= 5 { return nil }
        if shouldSkipAutocorrect(trimmed) { return nil }
        if lexicon.contains(lower) { return nil }

        guard let correction = lexicon.bestCorrection(for: lower) else { return nil }
        // Personal dictionary wins over lexicon corrections.
        if personalTerms.contains(where: { $0.lowercased() == correction }) {
            return EnglishCorrectionDecision(original: trimmed, replacement: matchCase(of: trimmed, to: correction))
        }
        let typedBoost = learnedBoosts[lower] ?? 0
        let correctionFreq = lexicon.frequency(of: correction) + (learnedBoosts[correction] ?? 0)
        // High-confidence gate: correction must clearly beat defending the typo.
        guard correctionFreq >= 80, correctionFreq > typedBoost + 40 else { return nil }
        return EnglishCorrectionDecision(
            original: trimmed,
            replacement: matchCase(of: trimmed, to: correction)
        )
    }

    public func nextWordComposition(_ context: EnglishSuggestionContext) -> TypingComposition {
        var ranked: [(text: String, score: Int, id: String)] = []
        var seen = Set<String>()

        func append(_ raw: String, baseScore: Int, tag: String) {
            let key = raw.lowercased()
            guard seen.insert(key).inserted else { return }
            let boost = context.learnedBoosts[key] ?? 0
            let personalBoost = context.personalTerms.contains { $0.lowercased() == key } ? 2_000 : 0
            ranked.append((raw, baseScore + boost + personalBoost, "\(tag)|\(key)"))
        }

        if let original = context.includeOriginalAfterCorrection {
            append(original, baseScore: 20_000, tag: "original")
        }

        if !context.previousWord.isEmpty {
            for (index, word) in lexicon.nextWords(after: context.previousWord, limit: 8).enumerated() {
                append(word, baseScore: 1_000 - index * 10, tag: "next")
            }
        }

        for term in context.personalTerms.prefix(4) {
            append(term, baseScore: 500, tag: "personal")
        }

        ranked.sort { $0.score > $1.score }
        let candidates = ranked.prefix(8).map {
            TypingCandidate(id: $0.id, text: $0.text, engineIndex: 0)
        }
        return TypingComposition(preedit: "", candidates: Array(candidates))
    }

    // MARK: - Helpers

    private func shouldSkipAutocorrect(_ typed: String) -> Bool {
        if typed.count <= 1 { return true }
        if typed.allSatisfy(\.isUppercase) { return true }
        if typed.contains(where: \.isNumber) { return true }
        if typed.contains("@") || typed.contains(".") || typed.contains("/") { return true }
        if typed.contains("-") || typed.contains("_") { return true }
        return false
    }

    private func matchCase(of sample: String, to word: String) -> String {
        if sample.allSatisfy(\.isUppercase) {
            return word.uppercased()
        }
        if let first = sample.first, first.isUppercase {
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        return word.lowercased()
    }
}
