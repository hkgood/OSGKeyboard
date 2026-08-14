// EnglishSuggestionEngine.swift
// OSGKeyboard · Shared
//
// Builds a 3-slot English QuickType board: verbatim / correction / completion
// (or next-word after commit). Space applies only the correction slot.

import Foundation

public struct EnglishSuggestionContext: Sendable {
    public var currentWord: String
    public var previousWord: String
    public var personalTerms: [String]
    public var learnedBoosts: [String: Int]
    public var includeOriginalAfterCorrection: String?
    /// Contacts / text replacements from `UILexicon`.
    public var systemWords: [String]
    public var systemCompletions: [String]
    public var systemGuesses: [String]

    public init(
        currentWord: String = "",
        previousWord: String = "",
        personalTerms: [String] = [],
        learnedBoosts: [String: Int] = [:],
        includeOriginalAfterCorrection: String? = nil,
        systemWords: [String] = [],
        systemCompletions: [String] = [],
        systemGuesses: [String] = []
    ) {
        self.currentWord = currentWord
        self.previousWord = previousWord
        self.personalTerms = personalTerms
        self.learnedBoosts = learnedBoosts
        self.includeOriginalAfterCorrection = includeOriginalAfterCorrection
        self.systemWords = systemWords
        self.systemCompletions = systemCompletions
        self.systemGuesses = systemGuesses
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
    public static let slotCount = 3
    /// In-vocabulary words only yield to a much more common transposition / neighbor.
    public static let inVocabularyFrequencyGap = 250

    private let lexicon: EnglishLexicon

    public init(lexicon: EnglishLexicon = .shared) {
        self.lexicon = lexicon
    }

    public func prepare() {
        lexicon.prepare()
    }

    /// Suggestions only while the user is actively typing an English word.
    public func compositionWhileTyping(_ context: EnglishSuggestionContext) -> TypingComposition {
        let prefix = context.currentWord
        guard !prefix.isEmpty else { return .empty }
        return makeBoard(context).composition
    }

    /// Decide whether to autocorrect on space / punctuation.
    public func correctionDecision(
        for typed: String,
        personalTerms: [String],
        learnedBoosts: [String: Int],
        previousWord: String = "",
        systemWords: [String] = [],
        systemGuesses: [String] = []
    ) -> EnglishCorrectionDecision? {
        let context = EnglishSuggestionContext(
            currentWord: typed,
            previousWord: previousWord,
            personalTerms: personalTerms,
            learnedBoosts: learnedBoosts,
            systemWords: systemWords,
            systemGuesses: systemGuesses
        )
        return makeBoard(context).decision
    }

    public func nextWordComposition(_ context: EnglishSuggestionContext) -> TypingComposition {
        var ranked: [(text: String, score: Int, role: TypingCandidateRole, quoted: Bool)] = []
        var seen = Set<String>()

        func append(_ raw: String, baseScore: Int, role: TypingCandidateRole, quoted: Bool = false) {
            let key = raw.lowercased()
            guard seen.insert(key).inserted else { return }
            let boost = context.learnedBoosts[key] ?? 0
            let personalBoost = isPersonal(key, in: context) ? 2_000 : 0
            ranked.append((raw, baseScore + boost + personalBoost, role, quoted))
        }

        if let original = context.includeOriginalAfterCorrection {
            append(original, baseScore: 20_000, role: .verbatim, quoted: true)
        }

        if !context.previousWord.isEmpty {
            for (index, word) in lexicon.nextWords(after: context.previousWord, limit: 8).enumerated() {
                append(word, baseScore: 1_200 - index * 10, role: .nextWord)
            }
        }

        for term in context.personalTerms.prefix(4) {
            append(term, baseScore: 500, role: .nextWord)
        }

        if ranked.filter({ $0.role == .nextWord }).isEmpty {
            for (index, word) in lexicon.topWords(limit: 6).enumerated() {
                append(word, baseScore: 200 - index, role: .nextWord)
            }
        }

        ranked.sort { $0.score > $1.score }
        let candidates = ranked.prefix(Self.slotCount).map {
            TypingCandidate(
                id: "\($0.role.rawValue)|\($0.text.lowercased())",
                text: $0.text,
                role: $0.role,
                isQuoted: $0.quoted
            )
        }
        return TypingComposition(preedit: "", candidates: Array(candidates))
    }

    public func isKnownWord(_ word: String, personalTerms: [String], systemWords: [String]) -> Bool {
        let lower = word.lowercased()
        if lexicon.contains(lower) { return true }
        if personalTerms.contains(where: { $0.lowercased() == lower }) { return true }
        if systemWords.contains(where: { $0.lowercased() == lower }) { return true }
        return false
    }

    // MARK: - Board

    private struct Board {
        var composition: TypingComposition
        var decision: EnglishCorrectionDecision?
    }

    private func makeBoard(_ context: EnglishSuggestionContext) -> Board {
        let typed = context.currentWord
        let decision = makeCorrectionDecision(context)
        var slots: [TypingCandidate] = []
        var seen = Set<String>()

        func add(_ text: String, role: TypingCandidateRole, quoted: Bool = false) {
            let key = text.lowercased()
            guard seen.insert(key).inserted else { return }
            slots.append(
                TypingCandidate(
                    id: "\(role.rawValue)|\(key)",
                    text: text,
                    role: role,
                    isQuoted: quoted
                )
            )
        }

        let known = isKnownWord(
            typed,
            personalTerms: context.personalTerms,
            systemWords: context.systemWords
        )
        add(typed, role: .verbatim, quoted: !known)

        if let decision {
            add(decision.replacement, role: .correction)
        }

        for term in context.personalTerms where term.lowercased().hasPrefix(typed.lowercased())
            && term.lowercased() != typed.lowercased() {
            add(term, role: .completion)
            if slots.count >= Self.slotCount { break }
        }

        for word in context.systemCompletions {
            let display = matchCase(of: typed, to: word)
            add(display, role: .completion)
            if slots.count >= Self.slotCount { break }
        }

        for word in lexicon.completions(prefix: typed, limit: 8) {
            add(matchCase(of: typed, to: word), role: .completion)
            if slots.count >= Self.slotCount { break }
        }

        let composition = TypingComposition(
            preedit: typed,
            candidates: Array(slots.prefix(Self.slotCount))
        )
        return Board(composition: composition, decision: decision)
    }

    private func makeCorrectionDecision(_ context: EnglishSuggestionContext) -> EnglishCorrectionDecision? {
        let typed = context.currentWord
        guard typed.count >= 3 else { return nil }
        let lower = typed.lowercased()

        if isProtectedToken(typed) { return nil }
        if isPersonal(lower, in: context) { return nil }
        if context.systemWords.contains(where: { $0.lowercased() == lower }) { return nil }
        if (context.learnedBoosts[lower] ?? 0) >= 5 { return nil }

        let inLexicon = lexicon.contains(lower)
        let typedFreq = lexicon.frequency(of: lower) + (context.learnedBoosts[lower] ?? 0)

        var pool = lexicon.scoredCorrections(for: lower, limit: 8)
        for guess in context.systemGuesses {
            let word = guess.lowercased()
            guard word != lower else { continue }
            if pool.contains(where: { $0.word == word }) { continue }
            guard let alignment = EnglishQWERTYProximity.align(typed: lower, candidate: word) else { continue }
            pool.append(
                EnglishScoredCorrection(
                    word: word,
                    spatialCost: alignment.cost,
                    frequency: max(lexicon.frequency(of: word), 1),
                    isTransposition: alignment.isTransposition,
                    isShortening: alignment.isShortening
                )
            )
        }

        var best: (EnglishScoredCorrection, Int)?
        for candidate in pool {
            guard allowsAutocorrect(
                typed: typed,
                replacement: candidate.word,
                inLexicon: inLexicon,
                typedFreq: typedFreq,
                candidate: candidate
            ) else { continue }
            var score = candidate.frequency * 2 - candidate.spatialCost
            if isPersonal(candidate.word, in: context) { score += 5_000 }
            score += context.learnedBoosts[candidate.word] ?? 0
            if lexicon.nextWords(after: context.previousWord).contains(candidate.word) {
                score += 80
            }
            if let current = best {
                if score > current.1 { best = (candidate, score) }
            } else {
                best = (candidate, score)
            }
        }

        guard let best else { return nil }
        let keepScore = inLexicon ? typedFreq * 2 : 0
        guard best.1 > keepScore + 40 else { return nil }
        return EnglishCorrectionDecision(
            original: typed,
            replacement: matchCase(of: typed, to: best.0.word)
        )
    }

    private func allowsAutocorrect(
        typed: String,
        replacement: String,
        inLexicon: Bool,
        typedFreq: Int,
        candidate: EnglishScoredCorrection
    ) -> Bool {
        if isTitleCase(typed) {
            // Teh → The is a same-length transposition. Rocky → Rock is not.
            guard candidate.isTransposition, !candidate.isShortening else { return false }
        }
        if inLexicon {
            let gap = candidate.frequency - typedFreq
            // Web-corpus dumps leak typos (`teh`, `adn`) at the floor of the
            // list. Real words like `form` sit much higher and must not yield
            // to `from`.
            let looksLikeLeakedTypo = typedFreq <= 680
            if candidate.isTransposition {
                return looksLikeLeakedTypo && gap >= 40
            }
            if typed.count == replacement.count,
               candidate.spatialCost <= EnglishQWERTYProximity.adjacentCost {
                return looksLikeLeakedTypo && gap >= Self.inVocabularyFrequencyGap
            }
            return false
        }
        return candidate.frequency > 0
    }

    private func isProtectedToken(_ typed: String) -> Bool {
        if typed.count <= 2 { return true }
        if typed.allSatisfy(\.isUppercase) { return true }
        if typed.contains(where: \.isNumber) { return true }
        if typed.contains("@") || typed.contains(".") || typed.contains("/") { return true }
        if typed.contains("-") || typed.contains("_") { return true }
        return false
    }

    private func isTitleCase(_ typed: String) -> Bool {
        guard let first = typed.first, first.isUppercase else { return false }
        let rest = typed.dropFirst()
        return !rest.isEmpty && rest.allSatisfy(\.isLowercase)
    }

    private func isPersonal(_ key: String, in context: EnglishSuggestionContext) -> Bool {
        context.personalTerms.contains { $0.lowercased() == key }
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
