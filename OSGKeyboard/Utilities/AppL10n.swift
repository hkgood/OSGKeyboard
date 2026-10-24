// AppL10n.swift
// OSGKeyboard · Main App
//
// Loads Localizable.strings from the host app bundle while honoring
// the in-app UI language override (not only the system language).

import Foundation
import OSGKeyboardShared

enum AppL10n {
    static func string(
        _ key: String,
        language: AppUILanguage? = nil
    ) -> String {
        let lang = language ?? resolvedUILanguage
        return AppUILanguage.localizedString(
            key,
            tableName: nil,
            bundle: .main,
            language: lang
        )
    }

    /// The in-app language override, or `.auto` when it cannot be read.
    ///
    /// `ProviderConfig` requires the App Group and traps without it — and the
    /// one screen the app renders in exactly that situation,
    /// `AppGroupErrorView`, is built entirely from localized strings. Resolving
    /// the language through `ProviderConfig.shared` there crashes the very
    /// screen that exists so a provisioning mistake does *not* become a crash
    /// loop. `.auto` follows the system language, which is the right answer
    /// when no stored preference is reachable anyway.
    ///
    /// Reads the persisted key directly rather than `ProviderConfig.shared`
    /// (main-actor isolated) because localized strings are also resolved off
    /// the main actor. `ProviderConfig` writes this key synchronously in its
    /// `uiLanguage` didSet, so both paths observe the same value.
    private static var resolvedUILanguage: AppUILanguage {
        guard let defaults = AppGroup.defaultsIfAvailable else { return .auto }
        return AppUILanguage.fromStored(
            defaults.string(forKey: AppGroupConfiguration.Keys.uiLanguage)
        )
    }

    static func format(
        _ key: String,
        language: AppUILanguage? = nil,
        _ args: CVarArg...
    ) -> String {
        String(
            format: string(key, language: language),
            locale: Locale.current,
            arguments: args
        )
    }
}
