// TypingHabitStore.swift
// OSGKeyboard · Shared
//
// Cross-language "forget" for implicit typing habits. Ranking stays
// language-specific (EnglishLearningStore vs librime userdb).

import Foundation

public enum TypingHabitStore {
    /// Clears English boosts, cross-language frequent terms, and Rime user dictionaries.
    /// Does not touch PersonalDictionary / osg_personal.
    public static func clearAll(
        englishStore: EnglishLearningStore = EnglishLearningStore(),
        frequentTermStore: FrequentTermStore = FrequentTermStore()
    ) async throws {
        englishStore.clear()
        frequentTermStore.clear()
        try await RimeResourceInstaller.shared.clearUserDictionary()
    }
}
