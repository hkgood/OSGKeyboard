// ExtL10n.swift
// OSGKeyboard · Keyboard Extension
//
// Loads strings from the keyboard extension bundle (not SwiftUI's default
// bundle, which may not see our Localizable.strings).

import Foundation
import SwiftUI

enum ExtL10n {
    private static let bundle = Bundle(for: KeyboardViewController.self)

    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func text(_ key: String) -> Text {
        Text(string(key))
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: args)
    }
}
