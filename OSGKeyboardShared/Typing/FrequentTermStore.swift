// FrequentTermStore.swift
// OSGKeyboard · Shared
//
// Small App Group sidecar for committed typing terms. Reading librime's
// LevelDB userdb while the keyboard owns it can race the engine, so the
// extension records eligible Chinese and English terms here and the host app
// ranks them for personal-dictionary suggestions.

import Foundation

public struct FrequentTerm: Codable, Equatable, Identifiable, Sendable {
    public var id: String { term.lowercased() }

    public let term: String
    public let commitCount: Int
    public let firstSeenAt: Date
    public let lastSeenAt: Date

    public init(
        term: String,
        commitCount: Int,
        firstSeenAt: Date,
        lastSeenAt: Date
    ) {
        self.term = term
        self.commitCount = commitCount
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
    }
}

/// Captures repeated eligible commits without writing to the curated
/// PersonalDictionary until the user explicitly confirms a suggestion.
public final class FrequentTermStore: @unchecked Sendable {
    public static let defaultsKey = "typing.frequentTerms.v2"
    public static let legacyRimeDefaultsKey = "rimeTyping.frequentTerms.v1"
    public static let minimumSuggestionCount = 2
    public static let maximumTrackedTerms = 256

    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = AppGroupStore().defaults) {
        self.defaults = defaults
    }

    public func recordCommittedText(_ text: String, at date: Date = Date()) {
        guard let term = Self.normalizedCandidate(from: text) else { return }

        lock.lock()
        defer { lock.unlock() }

        var terms = loadLocked()
        let key = term.lowercased()
        if let index = terms.firstIndex(where: { $0.term.lowercased() == key }) {
            let existing = terms[index]
            terms[index] = FrequentTerm(
                term: term,
                commitCount: min(10_000, existing.commitCount + 1),
                firstSeenAt: existing.firstSeenAt,
                lastSeenAt: date
            )
        } else {
            terms.append(
                FrequentTerm(
                    term: term,
                    commitCount: 1,
                    firstSeenAt: date,
                    lastSeenAt: date
                )
            )
        }

        terms.sort { lhs, rhs in
            if lhs.lastSeenAt != rhs.lastSeenAt {
                return lhs.lastSeenAt > rhs.lastSeenAt
            }
            return lhs.commitCount > rhs.commitCount
        }
        saveLocked(Array(terms.prefix(Self.maximumTrackedTerms)))
    }

    /// Repeated, recent commits that are not already curated.
    public func suggestions(
        excludingPersonalTerms personalTerms: Set<String>,
        limit: Int = 5
    ) -> [FrequentTerm] {
        guard limit > 0 else { return [] }
        let excluded = Set(personalTerms.map { $0.lowercased() })

        lock.lock()
        let terms = loadLocked()
        lock.unlock()

        return terms
            .filter {
                $0.commitCount >= Self.minimumSuggestionCount
                    && !excluded.contains($0.term.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.commitCount != rhs.commitCount {
                    return lhs.commitCount > rhs.commitCount
                }
                if lhs.lastSeenAt != rhs.lastSeenAt {
                    return lhs.lastSeenAt > rhs.lastSeenAt
                }
                return lhs.term.localizedStandardCompare(rhs.term) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

    public func clear() {
        lock.lock()
        defaults.removeObject(forKey: Self.defaultsKey)
        defaults.removeObject(forKey: Self.legacyRimeDefaultsKey)
        lock.unlock()
    }

    static func normalizedCandidate(from text: String) -> String? {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...32).contains(term.count),
              !commonTerms.contains(term.lowercased()),
              !term.unicodeScalars.contains(where: {
                  CharacterSet.whitespacesAndNewlines.contains($0)
              }) else {
            return nil
        }

        var semanticCharacterCount = 0
        for scalar in term.unicodeScalars {
            if HanScript.isIdeograph(scalar)
                || (scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)) {
                semanticCharacterCount += 1
                continue
            }
            // Product names, proper nouns, and English contractions commonly
            // contain these separators.
            guard allowedSeparators.contains(Character(String(scalar))) else {
                return nil
            }
        }
        return semanticCharacterCount >= 2 ? term : nil
    }

    private func loadLocked() -> [FrequentTerm] {
        if let data = defaults.data(forKey: Self.defaultsKey),
           let terms = try? JSONDecoder().decode([FrequentTerm].self, from: data) {
            return terms
        }

        guard let legacyData = defaults.data(forKey: Self.legacyRimeDefaultsKey),
              let legacyTerms = try? JSONDecoder().decode([FrequentTerm].self, from: legacyData) else {
            return []
        }

        // The legacy value has the same Codable shape, so migration only
        // changes its key and keeps every user's existing Chinese history.
        saveLocked(legacyTerms)
        defaults.removeObject(forKey: Self.legacyRimeDefaultsKey)
        return legacyTerms
    }

    private func saveLocked(_ terms: [FrequentTerm]) {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Avoid recommending ubiquitous conversational glue as a personal term.
    private static let commonTerms: Set<String> = [
        "a", "about", "after", "all", "also", "am", "an", "and", "any", "are",
        "as", "at", "be", "because", "been", "but", "by", "can", "could", "did",
        "do", "does", "for", "from", "get", "got", "had", "has", "have", "he",
        "her", "here", "him", "his", "how", "i", "if", "in", "is", "it", "its",
        "just", "me", "more", "my", "no", "not", "now", "of", "on", "one", "or",
        "our", "out", "she", "so", "some", "than", "that", "the", "their", "them",
        "then", "there", "they", "this", "to", "too", "up", "us", "was", "we",
        "were", "what", "when", "where", "which", "who", "why", "will", "with",
        "would", "you", "your",
        "一个", "一下", "不会", "不是", "什么", "他们", "但是", "你们", "你好",
        "可能", "可以", "因为", "好的", "如果", "已经", "应该", "怎么", "我们",
        "所以", "时候", "明天", "昨天", "有点", "没有", "然后", "现在", "知道",
        "自己", "觉得", "谢谢", "这个", "这里", "这样", "还是", "还有", "那个",
        "那里", "那样", "需要", "今天", "就是"
    ]

    private static let allowedSeparators: Set<Character> = ["-", "'", ".", "+", "#", "·"]
}
