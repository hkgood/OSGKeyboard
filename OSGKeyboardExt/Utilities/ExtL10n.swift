// ExtL10n.swift
// OSGKeyboard · Keyboard Extension
//
// Loads strings from Keyboard.strings in the extension bundle. We use a
// dedicated strings table (not Localizable.strings) because XcodeGen merges
// duplicate Localizable.strings variant groups into the main app target only.

import Foundation
import SwiftUI

enum ExtL10n {
    private static let table = "Keyboard"
    private static let bundle = Bundle(for: KeyboardViewController.self)

    static func string(_ key: String) -> String {
        let value = NSLocalizedString(
            key,
            tableName: table,
            bundle: bundle,
            value: key,
            comment: ""
        )
        return value
    }

    static func text(_ key: String) -> Text {
        Text(string(key))
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }
}
