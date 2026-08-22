// TypingHabitStore.swift
// OSGKeyboard · Shared
//
// Cross-language "forget" for implicit typing habits. Ranking stays
// language-specific (EnglishLearningStore vs librime userdb).

import Foundation

public enum TypingHabitStore {
    /// Clears English boosts and Chinese Rime user dictionaries.
    /// Does not touch PersonalDictionary / osg_personal.
    public static func clearAll(
        englishStore: EnglishLearningStore = EnglishLearningStore(),
        rimeFrequentTermStore: RimeFrequentTermStore = RimeFrequentTermStore()
    ) async throws {
        englishStore.clear()
        rimeFrequentTermStore.clear()
        try await RimeResourceInstaller.shared.clearUserDictionary()
    }
}
