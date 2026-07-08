// MacL10n.swift
// OSGKeyboard · Mac
//
// Bilingual UI strings for the macOS app. Reuses Shared.strings and
// respects the same `AppUILanguage` override as the iOS settings page.

import Foundation

enum MacL10n {
    static func string(_ key: String, language: AppUILanguage? = nil) -> String {
        SharedL10n.string(key, language: language)
    }

    static func format(_ key: String, language: AppUILanguage? = nil, _ args: CVarArg...) -> String {
        SharedL10n.format(key, language: language, args)
    }
}
