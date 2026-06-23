// SharedL10n.swift
// OSGKeyboard · Shared
//
// Localized strings shipped inside the shared framework (Shared.strings).
// Respects the in-app UI language override from App Group settings.

import Foundation

public enum SharedL10n {
    private static let table = "Shared"
    private static let container = Bundle(for: SharedBundleToken.self)

    public static func string(
        _ key: String,
        language: AppUILanguage? = nil
    ) -> String {
        let lang = language ?? AppGroupStore().uiLanguage
        let bundle = AppUILanguage.localizedBundle(in: container, language: lang)
        return NSLocalizedString(
            key,
            tableName: table,
            bundle: bundle,
            value: key,
            comment: ""
        )
    }

    public static func format(
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

private final class SharedBundleToken {}
