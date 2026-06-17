// AppGroup.swift
// OSGKeyboard · Shared
//
// App Group identifier shared between main app and keyboard extension.
// UserDefaults(suiteName:) and file containers use this.

import Foundation

public enum AppGroup {
    /// App Group container identifier (must match entitlements in both targets)
    public static let identifier = "group.com.osgkeyboard.shared"

    /// Shared UserDefaults instance for cross-process config.
    ///
    /// Falls back to `.standard` if the App Group isn't available (e.g.
    /// the user hasn't created the App Group in the Apple Developer
    /// portal, or Xcode hasn't downloaded a matching provisioning profile).
    /// In that mode, the keyboard extension will *not* see config written
    /// by the main app — but the main app itself stays usable so the user
    /// can fix the signing situation without the app crashing.
    public static var defaults: UserDefaults {
        if let d = UserDefaults(suiteName: identifier) {
            return d
        }
        #if DEBUG
        print("⚠️ App Group \(identifier) unavailable — falling back to .standard. " +
              "Add the App Group in your Apple Developer account and Xcode " +
              "Signing & Capabilities, then re-run.")
        #endif
        return .standard
    }
}
