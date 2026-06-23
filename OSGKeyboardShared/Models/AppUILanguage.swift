// AppUILanguage.swift
// OSGKeyboard · Shared
//
// In-app UI language override (main app + keyboard extension strings).
// Distinct from `localeId`, which controls speech recognition language.

import Foundation

public enum AppUILanguage: String, CaseIterable, Identifiable, Sendable, Codable {
    case auto
    case english = "en"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    public var labelKey: String {
        switch self {
        case .auto:    return "settings.appLanguage.auto"
        case .english: return "settings.appLanguage.english"
        case .chinese: return "settings.appLanguage.chinese"
        }
    }

    /// Locale for SwiftUI `.environment(\.locale, …)` in the host app.
    public var swiftUILocale: Locale {
        switch self {
        case .auto:
            return Locale.autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .chinese:
            return Locale(identifier: "zh-Hans")
        }
    }

    /// `.lproj` folder name used for manual bundle lookups (extension).
    public func resolvedLanguageCode(
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        switch self {
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        case .auto:
            if preferredLanguages.contains(where: { $0.hasPrefix("zh") }) {
                return "zh-Hans"
            }
            return "en"
        }
    }

    public static func fromStored(_ raw: String?) -> AppUILanguage {
        guard let raw, let value = AppUILanguage(rawValue: raw) else { return .auto }
        return value
    }

    /// Picks the best-matching `.lproj` inside `container` for this preference.
    public static func localizedBundle(
        in container: Bundle,
        language: AppUILanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Bundle {
        let code = language.resolvedLanguageCode(preferredLanguages: preferredLanguages)
        guard let path = container.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return container
        }
        return bundle
    }

    public static func localizedString(
        _ key: String,
        tableName: String?,
        bundle container: Bundle,
        language: AppUILanguage = AppGroupStore().uiLanguage
    ) -> String {
        let bundle = localizedBundle(in: container, language: language)
        return NSLocalizedString(
            key,
            tableName: tableName,
            bundle: bundle,
            value: key,
            comment: ""
        )
    }
}
