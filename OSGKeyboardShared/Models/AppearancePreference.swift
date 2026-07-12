// AppearancePreference.swift
// OSGKeyboard · Shared
//
// In-app light / dark preference for the iOS main app (iPhone + iPad).
// Mirrors macOS `MacAppearancePreference` but uses iOS Settings copy keys.
// Stored in standard UserDefaults (app-local); not synced via iCloud.

import SwiftUI

/// How the iOS host app resolves its colour scheme.
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable, Codable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// `nil` means follow the system — SwiftUI's `preferredColorScheme(nil)`.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    public var labelKey: String {
        switch self {
        case .system: return "settings.appearance.system"
        case .light:  return "settings.appearance.light"
        case .dark:   return "settings.appearance.dark"
        }
    }

    public static let storageKey = "config.appearancePreference"

    public static func fromStored(_ raw: String?) -> AppearancePreference {
        guard let raw, let value = AppearancePreference(rawValue: raw) else { return .system }
        return value
    }
}
