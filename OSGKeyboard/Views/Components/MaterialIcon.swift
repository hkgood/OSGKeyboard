// MaterialIcon.swift
// OSGKeyboard · Main App
//
// Google Material Icons (bundled MaterialIcons-Regular.ttf).
// Resolves the PostScript name at runtime and falls back to SF Symbols.

import SwiftUI
import UIKit
import CoreText

enum MaterialIconName {
    case keyboard
    case menuBook
    case settings
    case chevronRight
    case openInNew

    var codepoint: UInt32 {
        switch self {
        case .keyboard: return 0xE312
        case .menuBook: return 0xEA19
        case .settings: return 0xE8B8
        case .chevronRight: return 0xE5CC
        case .openInNew: return 0xE89E
        }
    }

    var sfSymbol: String {
        switch self {
        case .keyboard: return "keyboard"
        case .menuBook: return "book"
        case .settings: return "gearshape"
        case .chevronRight: return "chevron.right"
        case .openInNew: return "arrow.up.right.square"
        }
    }
}

enum MaterialIconsFont {
    private nonisolated(unsafe) static var cachedName: String?

    static var postScriptName: String? {
        if let cachedName { return cachedName }
        let candidates = [
            "MaterialIcons-Regular",
            "Material Icons Regular",
            "Material Icons"
        ]
        for name in candidates where UIFont(name: name, size: 17) != nil {
            cachedName = name
            return name
        }
        for family in UIFont.familyNames where family.localizedCaseInsensitiveContains("material") {
            for name in UIFont.fontNames(forFamilyName: family) {
                cachedName = name
                return name
            }
        }
        return nil
    }

    static func registerIfNeeded() {
        guard postScriptName == nil else { return }
        guard let url = Bundle.main.url(forResource: "MaterialIcons-Regular", withExtension: "ttf") else {
            return
        }
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        cachedName = nil
        _ = postScriptName
    }
}

struct MaterialIcon: View {
    let name: MaterialIconName
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let fontName = MaterialIconsFont.postScriptName,
               let scalar = UnicodeScalar(name.codepoint) {
                Text(String(scalar))
                    .font(.custom(fontName, size: size))
            } else {
                Image(systemName: name.sfSymbol)
                    .font(.system(size: size * 0.92, weight: .regular))
            }
        }
    }
}
