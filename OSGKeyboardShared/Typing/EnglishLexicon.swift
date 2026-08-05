// EnglishLexicon.swift
// OSGKeyboard · Shared
//
// Offline English word list + bigrams for the typing extension.
// Loaded once, kept compact for the keyboard RSS budget.

import Foundation

/// Ranked English lexicon used by autocomplete / autocorrect / next-word.
public final class EnglishLexicon: @unchecked Sendable {
    public static let shared = EnglishLexicon()

    /// Lowercased word → relative frequency (higher is more common).
    private var frequencies: [String: Int] = [:]
    /// Sorted lowercased words for prefix binary search.
    private var sortedWords: [String] = []
    /// previous(lower) → next-word candidates (lower).
    private var bigrams: [String: [String]] = [:]
    private var loaded = false
    private let lock = NSLock()

    public init() {}

    public func prepare() {
        lock.lock()
        defer { lock.unlock() }
        guard !loaded else { return }
        loadLexicon()
        loadBigrams()
        loaded = true
    }

    /// Release in-memory tables when leaving the typing surface (jetsam recovery).
    public func unload() {
        lock.lock()
        defer { lock.unlock() }
        frequencies.removeAll(keepingCapacity: false)
        sortedWords.removeAll(keepingCapacity: false)
        bigrams.removeAll(keepingCapacity: false)
        loaded = false
    }

    public var wordCount: Int {
        prepareIfNeeded()
        return sortedWords.count
    }

    public func frequency(of word: String) -> Int {
        prepareIfNeeded()
        return frequencies[word.lowercased()] ?? 0
    }

    public func contains(_ word: String) -> Bool {
        prepareIfNeeded()
        return frequencies[word.lowercased()] != nil
    }

    /// Prefix completions, highest frequency first.
    public func completions(prefix: String, limit: Int = 8) -> [String] {
        prepareIfNeeded()
        let needle = prefix.lowercased()
        guard !needle.isEmpty, limit > 0 else { return [] }

        var results: [(String, Int)] = []
        var index = lowerBound(needle)
        while index < sortedWords.count {
            let word = sortedWords[index]
            guard word.hasPrefix(needle) else { break }
            if word != needle {
                results.append((word, frequencies[word] ?? 0))
            }
            index += 1
            // Soft cap scan to keep keystroke path cheap.
            if results.count >= limit * 8 { break }
        }
        results.sort { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0 < rhs.0
        }
        return Array(results.prefix(limit).map(\.0))
    }

    /// Best edit-distance ≤ 2 correction, or nil when the typed word is fine.
    /// Uses Damerau–Levenshtein so adjacent swaps (teh → the) count as 1.
    /// Scans only same-initial-letter candidates (not the full frequency table).
    public func bestCorrection(for typed: String) -> String? {
        prepareIfNeeded()
        let needle = typed.lowercased()
        guard needle.count >= 2, let first = needle.first else { return nil }
        if frequencies[needle] != nil { return nil }

        var best: (word: String, distance: Int, freq: Int)?
        var index = lowerBound(String(first))
        while index < sortedWords.count {
            let word = sortedWords[index]
            guard word.first == first else { break }
            defer { index += 1 }
            guard abs(word.count - needle.count) <= 2 else { continue }
            let freq = frequencies[word] ?? 0
            let distance = damerauLevenshtein(needle, word, max: 2)
            guard distance > 0, distance <= 2 else { continue }
            if let current = best {
                if distance < current.distance
                    || (distance == current.distance && freq > current.freq) {
                    best = (word, distance, freq)
                }
            } else {
                best = (word, distance, freq)
            }
        }
        guard let best else { return nil }
        // Distance-2 corrections need a common word so rare near-misses don't win.
        if best.distance == 2, best.freq < 200 { return nil }
        return best.word
    }

    public func nextWords(after previous: String, limit: Int = 6) -> [String] {
        prepareIfNeeded()
        let key = previous.lowercased()
        guard let list = bigrams[key] else { return [] }
        return Array(list.prefix(limit))
    }

    // MARK: - Private

    private func prepareIfNeeded() {
        if !loaded { prepare() }
    }

    private func loadLexicon() {
        guard let url = Bundle(for: EnglishLexicon.self)
            .url(forResource: "english_lexicon", withExtension: "tsv", subdirectory: nil)
            ?? Bundle(for: EnglishLexicon.self)
            .url(forResource: "english_lexicon", withExtension: "tsv")
            ?? Bundle.main.url(forResource: "english_lexicon", withExtension: "tsv")
        else {
            return
        }
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return }
        var map: [String: Int] = [:]
        for line in data.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let freq = Int(parts[1]) else { continue }
            let word = String(parts[0]).lowercased()
            guard !word.isEmpty else { continue }
            map[word] = freq
        }
        frequencies = map
        sortedWords = map.keys.sorted()
    }

    private func loadBigrams() {
        guard let url = Bundle(for: EnglishLexicon.self)
            .url(forResource: "english_bigrams", withExtension: "tsv")
            ?? Bundle.main.url(forResource: "english_bigrams", withExtension: "tsv")
        else {
            return
        }
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return }
        var map: [String: [String]] = [:]
        for line in data.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let prev = String(parts[0]).lowercased()
            let nexts = parts[1].split(whereSeparator: \.isWhitespace).map { String($0).lowercased() }
            guard !prev.isEmpty, !nexts.isEmpty else { continue }
            map[prev] = nexts
        }
        bigrams = map
    }

    private func lowerBound(_ prefix: String) -> Int {
        var low = 0
        var high = sortedWords.count
        while low < high {
            let mid = (low + high) / 2
            if sortedWords[mid] < prefix {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }

    /// Damerau–Levenshtein with early exit when distance would exceed `max`.
    private func damerauLevenshtein(_ a: String, _ b: String, max: Int) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let aCount = aChars.count
        let bCount = bChars.count
        if abs(aCount - bCount) > max { return max + 1 }

        var prevPrev = [Int](repeating: 0, count: bCount + 1)
        var prev = Array(0...bCount)
        for i in 1...aCount {
            var current = [Int](repeating: 0, count: bCount + 1)
            current[0] = i
            var rowMin = current[0]
            for j in 1...bCount {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                var value = min(
                    prev[j] + 1,
                    current[j - 1] + 1,
                    prev[j - 1] + cost
                )
                // Adjacent transposition
                if i > 1, j > 1,
                   aChars[i - 1] == bChars[j - 2],
                   aChars[i - 2] == bChars[j - 1] {
                    value = min(value, prevPrev[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > max { return max + 1 }
            prevPrev = prev
            prev = current
        }
        return prev[bCount]
    }
}
