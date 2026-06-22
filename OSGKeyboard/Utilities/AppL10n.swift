// AppL10n.swift
// OSGKeyboard · Main App
//
// Loads Localizable.strings from the host app bundle while honoring
// the in-app UI language override (not only the system language).

import Foundation
import SwiftUI
import OSGKeyboardShared

enum AppL10n {
    static func string(
        _ key: String,
        language: AppUILanguage? = nil
    ) -> String {
        let lang = language ?? ProviderConfig.shared.uiLanguage
        return AppUILanguage.localizedString(
            key,
            tableName: nil,
            bundle: .main,
            language: lang
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

    static func text(_ key: String) -> Text {
        Text(LocalizedStringKey(key))
    }
}
