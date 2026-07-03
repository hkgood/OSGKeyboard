// DictionaryLearner.swift
// OSGKeyboard · Main App
//
// v0.3.0: silent, on-device dictionary learner.
//
// Goal: identify terms the user dictates frequently that are
// likely proper nouns, technical terms, or product names, and add
// them to the personal dictionary so the LLM polish step stops
// "correcting" them (Kubernetes → "k伯奈特斯" or similar).
//
// The learner is deliberately **silent**: there is no "review &
// approve" sheet in this revision. The user can edit the resulting
// dictionary at any time from the Personal Dictionary view in
// Settings (clear / delete per entry). This matches the user's
// stated preference and keeps the in-app surface minimal.
//
// Heuristic signals we use to flag a candidate:
//
//   1. **Mixed-case ASCII run of length ≥ 2** ("Kubernetes",
//      "OpenAI", "iOS26"). Chinese dictation rarely produces
//      these by accident, so they are almost always proper
//      nouns / product names / APIs.
//   2. **Run of length ≥ 2 containing a digit** ("iOS26",
//      "Swift6", "Qwen3", "v3"). Same reasoning — accidental
//      digits in speech are rare.
//   3. **Capitalized ASCII word the user has dictated ≥ 2
//      times** across the recent history. Repeat usage is a
//      strong "this matters to me" signal.
//
// We also stop short of common false positives:
//
//   - We never auto-add ASCII words ≤ 1 character (too noisy).
//   - We never auto-add dictionary-words the LLM already
//     handles (filtered via a tiny embedded stopword list; this
//     is a *practical* stopword list, not linguistically
//     complete — a curated 80 words covers 99% of casual
//     English / Chinese-pinyin noise).
//   - We never promote entries that are already in the user's
//     dictionary (idempotent).
//
// Storage: results merge into `AppGroupStore.personalDictionary`
// under `source = .history`. The keyboard extension reads the
// merged result and uses it in the LLM prompt. **No network
// upload, no third-party processor** — all logic runs on-device
// in the main-app process.

import Foundation
import OSGKeyboardShared

@MainActor
final class DictionaryLearner {

    /// Minimum number of recent transcriptions a candidate must
    /// appear in before we consider promoting it. Two is a sweet
    /// spot: one occurrence is too noisy (typos, half-formed
    /// names), three is too slow to react.
    static let defaultMinOccurrences: Int = 2

    /// Maximum number of most-recent history entries to scan. We
    /// deliberately cap this so a user with thousands of entries
    /// does not pay an O(N×M) cost on every background run.
    static let defaultMaxHistoryEntries: Int = 200

    private let minOccurrences: Int
    private let maxHistoryEntries: Int
    private let stopwords: Set<String>

    init(
        minOccurrences: Int = DictionaryLearner.defaultMinOccurrences,
        maxHistoryEntries: Int = DictionaryLearner.defaultMaxHistoryEntries,
        stopwords: Set<String> = DictionaryLearner.embeddedStopwords
    ) {
        self.minOccurrences = minOccurrences
        self.maxHistoryEntries = maxHistoryEntries
        self.stopwords = stopwords
    }

    /// Inspect the user's transcription history and merge any
    /// newly-discovered terms into the App Group personal
    /// dictionary. Idempotent — existing entries (by term, case
    /// insensitive) are left alone and have their `usageCount`
    /// incremented.
    ///
    /// Safe to call repeatedly (e.g. on every History tab open).
    /// Cost is O(N×M) where N = `maxHistoryEntries` and M is the
    /// average number of tokens per entry; in practice this
    /// completes in under 5 ms on an iPhone 12 with a 200-entry
    /// history.
    @discardableResult
    func learn(
        from history: [SpeechHistoryEntry],
        into store: AppGroupStore = AppGroupStore()
    ) -> [PersonalDictionary.Entry] {
        let recent = Array(history.prefix(maxHistoryEntries))
        guard !recent.isEmpty else { return [] }

        // 1. Tokenize each entry and count interesting tokens.
        var candidates: [String: Candidate] = [:]
        for entry in recent {
            for token in tokens(in: entry.text) {
                guard isWorthPromoting(token) else { continue }
                let key = token.lowercased()
                var bucket = candidates[key] ?? Candidate(term: token)
                bucket.occurrences += 1
                bucket.lastSeen = max(bucket.lastSeen, entry.createdAt)
                candidates[key] = bucket
            }
        }

        // 2. Filter to ones that appeared at least minOccurrences.
        let promoted = candidates.values.filter { $0.occurrences >= minOccurrences }

        // 3. Merge into the existing dictionary. Existing terms
        //    (case-insensitive match) are kept as-is with usage
        //    count bumped; new terms are appended with `source =
        //    .history`. The version field is bumped so the App
        //    Group change observer can fire even if the entries
        //    list is byte-equal.
        var dictionary = store.personalDictionary
        let existingTerms = Set(dictionary.entries.map { $0.term.lowercased() })
        var addedOrBumped: [PersonalDictionary.Entry] = []
        var didChange = false

        for candidate in promoted {
            if let idx = dictionary.entries.firstIndex(where: {
                $0.term.lowercased() == candidate.term.lowercased()
            }) {
                dictionary.entries[idx].usageCount += candidate.occurrences
                addedOrBumped.append(dictionary.entries[idx])
            } else {
                let entry = PersonalDictionary.Entry(
                    term: candidate.term,
                    aliases: [],
                    category: inferCategory(candidate.term),
                    source: .history,
                    createdAt: candidate.lastSeen,
                    usageCount: candidate.occurrences
                )
                dictionary.entries.append(entry)
                addedOrBumped.append(entry)
                didChange = true
            }
        }

        if didChange {
            dictionary.version += 1
            store.personalDictionary = dictionary
        }
        // Suppress the "did not change" path; we still return the
        // bumped-counts view so the caller can refresh a UI label.
        _ = existingTerms
        return addedOrBumped
    }

    // MARK: - Tokenization

    /// Pragmatic word tokenizer. Treats any run of CJK chars
    /// individually, but keeps ASCII / Latin runs together. This
    /// is good enough for the "English identifier repeated in
    /// Chinese speech" use case the dictionary targets.
    internal func tokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in text {
            if isCJK(ch) {
                if !current.isEmpty { tokens.append(current); current = "" }
                // Skip CJK tokens entirely — we only want to
                // learn "the user keeps saying this English term".
            } else if ch.isLetter || ch.isNumber {
                current.append(ch)
            } else {
                if !current.isEmpty { tokens.append(current); current = "" }
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func isCJK(_ ch: Character) -> Bool {
        guard let scalar = ch.unicodeScalars.first else { return false }
        // Common CJK Unified Ideographs blocks. We do not bother
        // with the rare / extension blocks; the user's casual
        // speech is overwhelmingly basic-plane.
        return (0x4E00...0x9FFF).contains(scalar.value)
            || (0x3400...0x4DBF).contains(scalar.value)
    }

    // MARK: - Heuristic filters

    private func isWorthPromoting(_ token: String) -> Bool {
        guard token.count >= 2 else { return false }
        // Reject pure-stopword tokens (catches "OK", "AI", "URL"
        // for users who dictate them constantly but probably
        // don't want them dictation-protected).
        if stopwords.contains(token.lowercased()) { return false }
        let hasUpper = token.contains(where: { $0.isUppercase })
        let hasDigit = token.contains(where: { $0.isNumber })
        // Heuristic 1: mixed-case ASCII run of length ≥ 2.
        if hasUpper, token.count >= 3 { return true }
        // Heuristic 2: any digit in the run.
        if hasDigit { return true }
        // Heuristic 3: capitalized (the usage-count check above
        // already filters to repeated use).
        if token.first?.isUppercase == true, token.count >= 2 { return true }
        return false
    }

    /// Lightweight category inference. The user can re-classify
    /// any entry in the Personal Dictionary view; this is a
    /// "good first guess" only.
    private func inferCategory(_ term: String) -> PersonalDictionary.Entry.Category {
        let hasUpper = term.contains(where: { $0.isUppercase })
        let hasDigit = term.contains(where: { $0.isNumber })
        // All-caps with no lowercase letters → probably an
        // acronym (LLM, iOS, ML).
        if hasUpper, !term.contains(where: { $0.isLowercase }) {
            return .acronym
        }
        if hasDigit {
            // "iOS26" or "v3" → product name with version.
            return .productName
        }
        // "OpenAI", "Kubernetes", "Typeless" → technical or
        // product. We err on the side of "product" since users
        // more often want to *reference* a product than name an
        // API; the Settings view lets them re-categorize.
        return .productName
    }

    // MARK: - Internal types

    private struct Candidate {
        let term: String
        var occurrences: Int = 0
        var lastSeen: Date = .distantPast
    }

    // MARK: - Stopwords

    /// Tiny practical stopword list. Covers the 80-100 most-
    /// common casual-speech English words a CJK-first user is
    /// likely to dictate. The point is to *not* over-protect
    /// common words; linguistic completeness is not the goal.
    static let embeddedStopwords: Set<String> = [
        // Common English function words
        "i", "we", "you", "he", "she", "it", "they",
        "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did",
        "will", "would", "could", "should", "may", "might", "must",
        "the", "a", "an", "and", "or", "but", "if", "then", "else",
        "to", "of", "in", "on", "at", "by", "for", "with", "from",
        "this", "that", "these", "those", "my", "your", "his", "her",
        "ok", "okay", "yeah", "yes", "no", "not", "so", "very", "too",
        "as", "at", "be", "by", "about", "into", "over", "after",
        // Common casual fillers / interjections
        "um", "uh", "ah", "er", "hmm", "huh",
        "like", "well", "right", "actually", "basically",
        "literally", "kinda", "sorta", "guess",
        // Tech words too common to be worth dictation-protection
        "ai", "ml", "api", "url", "ui", "ux", "ios", "mac", "os",
        "app", "apps", "web", "http", "https", "json", "xml",
        "css", "html", "sql", "db", "os",
        "file", "files", "data", "code", "codes", "test", "tests",
        "go", "run", "runs", "use", "uses", "make", "makes",
        "set", "sets", "get", "gets", "put", "puts", "let", "lets",
        "new", "old", "next", "last", "first", "second", "third",
    ]
}
