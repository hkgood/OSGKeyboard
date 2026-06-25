// TranslationLanguage.swift
// OSGKeyboard · Shared
//
// Catalog of target languages the translation feature can produce.
//
// Kept deliberately small (~10 entries) to match the kind of choices
// the user makes in the Settings picker / keyboard chip. We don't try
// to expose every BCP-47 locale — the prompt just needs a target
// language name, and a curated list reads better than a 100-row scroll.
//
// `id` is what gets persisted to the App Group. `promptLanguageName`
// is the human-readable target name injected into the prompt (e.g.
// the LLM sees "English", not "en"). `nativeName` is the endonym we
// show in the picker UI ("日本語" instead of "Japanese").

import Foundation

public struct TranslationLanguage: Identifiable, Hashable, Sendable {
    public let id: String
    public let promptLanguageName: String
    public let nativeName: String

    public init(id: String, promptLanguageName: String, nativeName: String) {
        self.id = id
        self.promptLanguageName = promptLanguageName
        self.nativeName = nativeName
    }
}

public enum TranslationLanguageCatalog {
    /// Default target language id used on fresh installs.
    public static let defaultLocaleId = "en"

    /// Curated set. Order matters — the picker / chip render top-to-
    /// bottom, and `defaultLocaleId` is the default selection.
    public static let all: [TranslationLanguage] = [
        TranslationLanguage(id: "en",    promptLanguageName: "English",  nativeName: "English"),
        TranslationLanguage(id: "zh-Hans", promptLanguageName: "Simplified Chinese", nativeName: "简体中文"),
        TranslationLanguage(id: "zh-Hant", promptLanguageName: "Traditional Chinese", nativeName: "繁體中文"),
        TranslationLanguage(id: "ja",    promptLanguageName: "Japanese", nativeName: "日本語"),
        TranslationLanguage(id: "ko",    promptLanguageName: "Korean",   nativeName: "한국어"),
        TranslationLanguage(id: "fr",    promptLanguageName: "French",   nativeName: "Français"),
        TranslationLanguage(id: "de",    promptLanguageName: "German",   nativeName: "Deutsch"),
        TranslationLanguage(id: "es",    promptLanguageName: "Spanish",  nativeName: "Español"),
        TranslationLanguage(id: "ru",    promptLanguageName: "Russian",  nativeName: "Русский"),
        TranslationLanguage(id: "pt",    promptLanguageName: "Portuguese", nativeName: "Português"),
    ]

    /// Resolve a stored locale id to its catalog entry. Falls back to
    /// `defaultLocaleId` when the id is missing or unknown — matches the
    /// pattern used elsewhere (e.g. `ASRLocaleLabels`) so the keyboard
    /// never crashes on a stale persisted value.
    public static func resolve(_ id: String) -> TranslationLanguage {
        if let match = all.first(where: { $0.id == id }) {
            return match
        }
        return all.first { $0.id == defaultLocaleId } ?? all[0]
    }
}