// EnglishLearningStore.swift
// OSGKeyboard · Shared
//
// Lightweight per-word boost counts for English typing. Lives in the App
// Group so the extension can read/write without touching PersonalDictionary.

import Foundation

/// Records accepted suggestions / defended originals for ranking.
public final class EnglishLearningStore: @unchecked Sendable {
    public static let defaultsKey = "englishTyping.learnedBoosts.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroupStore().defaults) {
        self.defaults = defaults
    }

    public func boost(for word: String) -> Int {
        let key = word.lowercased()
        guard !key.isEmpty else { return 0 }
        return snapshot()[key] ?? 0
    }

    public func recordAcceptance(of word: String, amount: Int = 3) {
        mutate(word: word, delta: amount)
    }

    public func recordDefense(of word: String, amount: Int = 5) {
        // User rejected autocorrect / insisted on original spelling.
        mutate(word: word, delta: amount)
    }

    public func snapshot() -> [String: Int] {
        (defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int]) ?? [:]
    }

    public func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    private func mutate(word: String, delta: Int) {
        let key = word.lowercased()
        guard !key.isEmpty else { return }
        var map = snapshot()
        map[key] = min(10_000, (map[key] ?? 0) + delta)
        defaults.set(map, forKey: Self.defaultsKey)
    }
}
