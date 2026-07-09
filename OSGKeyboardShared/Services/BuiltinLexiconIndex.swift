// BuiltinLexiconIndex.swift
// OSGKeyboard · Shared
//
// In-memory index over bundled `phrases.tsv` (~10k computer terms).
// macOS local ASR consumes a Top-N subset; the full index also backs
// polish supplements and future retrieval.

import Foundation

public final class BuiltinLexiconIndex: @unchecked Sendable {

    public struct Term: Sendable, Equatable {
        public let word: String
        public let pinyin: String
        public let source: String
        public let weight: Int
    }

    public static let shared = BuiltinLexiconIndex()

    private let lock = NSLock()
    private var cachedTerms: [Term]?
    private let injectedURL: URL?

    /// Production singleton loads from the app bundle.
    private init() {
        injectedURL = nil
    }

    /// Test / preview hook with an explicit TSV file or inline fixture.
    init(fixtureURL: URL) {
        injectedURL = fixtureURL
    }

    /// Parse TSV content without touching the bundle (unit tests).
    public static func parseTSV(_ content: String) -> [Term] {
        var terms: [Term] = []
        terms.reserveCapacity(256)

        for (lineIndex, line) in content.split(whereSeparator: \.isNewline).enumerated() {
            if lineIndex == 0, line.hasPrefix("word\t") { continue }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 4 else { continue }
            let word = String(columns[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            let pinyin = String(columns[1])
            let source = String(columns[2])
            let weight = Int(columns[3]) ?? 1
            terms.append(Term(word: word, pinyin: pinyin, source: source, weight: weight))
        }
        return terms
    }

    public func termCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return loadTermsLocked().count
    }

    /// Returns canonical words ranked for ASR bias injection.
    public func topTerms(
        limit: Int,
        minimumWeight: Int = 4,
        preferredSources: Set<String>? = nil
    ) -> [String] {
        guard limit > 0 else { return [] }

        lock.lock()
        let all = loadTermsLocked()
        lock.unlock()

        let filtered = all.filter { term in
            guard term.weight >= minimumWeight else { return false }
            if let preferredSources, !preferredSources.isEmpty {
                return preferredSources.contains(term.source)
            }
            return true
        }

        let ranked = filtered.sorted { lhs, rhs in
            let leftScore = Self.rankingScore(lhs)
            let rightScore = Self.rankingScore(rhs)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
        }

        var seen = Set<String>()
        var words: [String] = []
        words.reserveCapacity(min(limit, ranked.count))
        for term in ranked {
            let key = term.word.lowercased()
            guard seen.insert(key).inserted else { continue }
            words.append(term.word)
            if words.count >= limit { break }
        }
        return words
    }

    // MARK: - Private

    private func loadTermsLocked() -> [Term] {
        if let cachedTerms { return cachedTerms }
        let loaded: [Term]
        if let injectedURL {
            loaded = Self.load(from: injectedURL)
        } else if let url = Self.locateBundledPhrasesURL() {
            loaded = Self.load(from: url)
        } else {
            loaded = []
        }
        cachedTerms = loaded
        return loaded
    }

    private static func load(from url: URL) -> [Term] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseTSV(content)
    }

    private static func locateBundledPhrasesURL() -> URL? {
        let candidates: [Bundle] = [Bundle.main, Bundle(for: BuiltinLexiconIndex.self)]
        for bundle in candidates {
            if let url = bundle.url(
                forResource: "phrases",
                withExtension: "tsv",
                subdirectory: "CustomLanguageModel/v1"
            ) {
                return url
            }
            if let url = bundle.url(forResource: "phrases", withExtension: "tsv") {
                return url
            }
        }
        return nil
    }

    private static func rankingScore(_ term: Term) -> Int {
        var score = term.weight * 100
        if containsLatinLetters(term.word) { score += 50 }
        if term.word.count <= 8 { score += 10 }
        return score
    }

    private static func containsLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.isASCII && CharacterSet.letters.contains(scalar)
        }
    }
}
