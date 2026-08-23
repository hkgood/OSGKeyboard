// TranslationLanguage.swift
// OSGKeyboard · Shared
//
// Catalog of target languages the translation feature can produce.
//
// Kept deliberately small (~10 entries) to match the kind of choices
// the user makes in the Settings picker / keyboard menu. We don't try
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

    /// One-character Chinese token for compact chips such as「中译英」.
    public var chineseShort: String {
        switch id {
        case "en": return "英"
        case "zh-Hans": return "中"
        case "zh-Hant": return "繁"
        case "ja": return "日"
        case "ko": return "韩"
        case "fr": return "法"
        case "de": return "德"
        case "es": return "西"
        case "ru": return "俄"
        case "pt": return "葡"
        default: return nativeName
        }
    }

    /// Country-style English code for compact chips such as「To JP」.
    public var englishShort: String {
        switch id {
        case "en": return "EN"
        case "zh-Hans": return "CN"
        case "zh-Hant": return "TW"
        case "ja": return "JP"
        case "ko": return "KR"
        case "fr": return "FR"
        case "de": return "DE"
        case "es": return "ES"
        case "ru": return "RU"
        case "pt": return "PT"
        default: return id.uppercased()
        }
    }

    /// True when this target is a Chinese script (简体 or 繁體).
    public var isChineseScript: Bool {
        id == "zh-Hans" || id == "zh-Hant"
    }
}

public enum TranslationLanguageCatalog {
    /// Sentinel id for "don't translate" — the default selection in the
    /// picker. Picked over an `Optional<TranslationLanguage>` so the
    /// single-row `Picker` binding and keyboard menu stay a plain `String`.
    public static let offLocaleId = "off"
    /// Default target language id used on fresh installs when translation
    /// is enabled. The picker still defaults to `offLocaleId` — this is
    /// only the language we'd fall back to if a stale "on" state is
    /// recovered without a remembered target.
    public static let defaultLocaleId = "en"

    /// Curated set. Order matters — the picker / menu render top-to-
    /// bottom, with `offLocaleId` ("不翻译") at the very top so the
    /// "turn off" action is one tap away from any enabled state.
    public static let all: [TranslationLanguage] = [
        TranslationLanguage(id: offLocaleId, promptLanguageName: "", nativeName: ""),
        TranslationLanguage(id: "en", promptLanguageName: "English", nativeName: "English"),
        TranslationLanguage(id: "zh-Hans", promptLanguageName: "Simplified Chinese", nativeName: "简体中文"),
        TranslationLanguage(id: "zh-Hant", promptLanguageName: "Traditional Chinese", nativeName: "繁體中文"),
        TranslationLanguage(id: "ja", promptLanguageName: "Japanese", nativeName: "日本語"),
        TranslationLanguage(id: "ko", promptLanguageName: "Korean", nativeName: "한국어"),
        TranslationLanguage(id: "fr", promptLanguageName: "French", nativeName: "Français"),
        TranslationLanguage(id: "de", promptLanguageName: "German", nativeName: "Deutsch"),
        TranslationLanguage(id: "es", promptLanguageName: "Spanish", nativeName: "Español"),
        TranslationLanguage(id: "ru", promptLanguageName: "Russian", nativeName: "Русский"),
        TranslationLanguage(id: "pt", promptLanguageName: "Portuguese", nativeName: "Português")
    ]

    /// True when the given id is the "off" sentinel. Used by the picker
    /// to flip `translationEnabled` and by the pipeline to skip the
    /// translate prompt.
    public static func isOff(_ id: String) -> Bool {
        id == offLocaleId
    }

    /// Resolve a stored locale id to its catalog entry. Falls back to
    /// `offLocaleId` (the picker default) when the id is missing or
    /// unknown — matches the pattern used elsewhere (e.g.
    /// `ASRLocaleLabels`) so the keyboard never crashes on a stale
    /// persisted value, and the picker lands on the safe "off" state
    /// instead of an arbitrary language.
    public static func resolve(_ id: String) -> TranslationLanguage {
        if let match = all.first(where: { $0.id == id }) {
            return match
        }
        return all.first { $0.id == offLocaleId } ?? all[0]
    }
}

/// Resolves the device's first preferred language for clipboard translation.
/// This intentionally ignores the optional post-dictation translation target.
public enum SystemLanguageResolver {
    public static func primaryIdentifier(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        normalizedIdentifier(
            preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        )
    }

    public static func promptLanguageName(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let identifier = primaryIdentifier(preferredLanguages: preferredLanguages)
        if let known = TranslationLanguageCatalog.all.first(where: { $0.id == identifier }) {
            return known.promptLanguageName
        }
        return Locale(identifier: "en").localizedString(forIdentifier: identifier)
            ?? identifier
    }

    public static func displayLanguageName(
        uiLanguage: AppUILanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let identifier = primaryIdentifier(preferredLanguages: preferredLanguages)
        let displayLocale = Locale(identifier: uiLanguage.resolvedLanguageCode())
        return displayLocale.localizedString(forIdentifier: identifier)
            ?? promptLanguageName(preferredLanguages: preferredLanguages)
    }

    public static func isSameLanguage(
        sourceIdentifier: String,
        targetIdentifier: String
    ) -> Bool {
        let source = normalizedIdentifier(sourceIdentifier)
        let target = normalizedIdentifier(targetIdentifier)
        if source.hasPrefix("zh"), target.hasPrefix("zh") {
            let sourceScript = chineseScript(in: source)
            let targetScript = chineseScript(in: target)
            return sourceScript == nil || targetScript == nil || sourceScript == targetScript
        }
        return source == target
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        let language = Locale.Language(identifier: identifier)
        guard let rawCode = language.languageCode?.identifier else {
            return identifier.lowercased()
        }
        let code = rawCode.lowercased()
        guard code == "zh" || code == "yue" else { return code }

        let script = language.script?.identifier.lowercased()
        let region = Locale(identifier: identifier).region?.identifier.uppercased()
        if script == "hant" || ["HK", "MO", "TW"].contains(region) {
            return "zh-Hant"
        }
        if script == "hans" || ["CN", "MY", "SG"].contains(region) {
            return "zh-Hans"
        }
        return "zh"
    }

    private static func chineseScript(in identifier: String) -> String? {
        let normalized = identifier.lowercased()
        if normalized.contains("hant") { return "Hant" }
        if normalized.contains("hans") { return "Hans" }
        return nil
    }
}
