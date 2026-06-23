// ExtL10n.swift
// OSGKeyboard · Keyboard Extension
//
// Loads strings from Keyboard.strings in the extension bundle. We use a
// dedicated strings table (not Localizable.strings) because XcodeGen merges
// duplicate Localizable.strings variant groups into the main app target only.

import Foundation
import SwiftUI
import OSGKeyboardShared

enum ExtL10n {
    private static let table = "Keyboard"
    private static let container = Bundle(for: KeyboardViewController.self)

    private static var bundle: Bundle {
        AppUILanguage.localizedBundle(
            in: container,
            language: AppGroupStore().uiLanguage
        )
    }

    static func string(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: table,
            bundle: bundle,
            value: key,
            comment: ""
        )
    }

    static func text(_ key: String) -> Text {
        Text(string(key))
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }
}
