// MacAppearance.swift
// OSGKeyboard · Mac
//
// User-facing light / dark preference for the desktop app. Stored locally
// (Mac-only switch for now); can be promoted into `SyncedAppSettings` later
// if iPad / cross-device appearance sync is wanted.

import AppKit
import SwiftUI

/// How the macOS app resolves its colour scheme.
enum MacAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `nil` means "follow the system", matching SwiftUI's convention where
    /// `preferredColorScheme(nil)` defers to the environment.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    /// The matching AppKit appearance so window chrome, traffic lights and
    /// the menu-bar popover follow the same choice as the SwiftUI content.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    var labelKey: String {
        switch self {
        case .system: return "mac.appearance.system"
        case .light:  return "mac.appearance.light"
        case .dark:   return "mac.appearance.dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    /// `@AppStorage` key shared by the app shell and the settings switch.
    static let storageKey = "mac.appearancePreference"

    static var current: MacAppearancePreference {
        MacAppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: storageKey) ?? ""
        ) ?? .system
    }

    /// Push the preference into AppKit so non-SwiftUI chrome (title bar,
    /// popover) tracks it too. Safe to call on the main actor at any time.
    @MainActor
    static func applyToApp(_ preference: MacAppearancePreference) {
        NSApp?.appearance = preference.nsAppearance
        NSApp?.windows.forEach { window in
            window.appearance = preference.nsAppearance
            window.contentView?.needsDisplay = true
            window.contentView?.subviews.forEach { $0.needsDisplay = true }
        }
    }
}
