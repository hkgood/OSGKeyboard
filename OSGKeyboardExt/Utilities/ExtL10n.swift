// ExtL10n.swift
// OSGKeyboard · Keyboard Extension
//
// Loads strings from the extension bundle. Replaces the old KeyboardL10n
// hard-coded fallback map — keys live in Localizable.strings.

import Foundation

enum ExtL10n {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }
}
