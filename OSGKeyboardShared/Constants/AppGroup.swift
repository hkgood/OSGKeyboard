// AppGroup.swift
// OSGKeyboard · Shared
//
// App Group identifier shared between main app and keyboard extension.
// UserDefaults(suiteName:) and file containers use this.

import Foundation

public enum AppGroup {
    /// App Group container identifier (must match entitlements in both targets)
    public static let identifier = "group.com.osgkeyboard.shared"

    /// Whether the App Group container is available on this device.
    ///
    /// Cached at first read — the underlying `UserDefaults(suiteName:)`
    /// call is cheap, but main-app startup and every keyboard-extension
    /// read hit it, so we memoize the result.
    ///
    /// Production code paths MUST go through `isAvailable` first and
    /// surface a friendly error view (e.g. `AppGroupErrorView`) on the
    /// main app, or the keyboard extension's persisted-locale load.
    /// Calling `defaults` directly when the group is missing will trip
    /// the DEBUG `fatalError` below — that path is reserved for
    /// developer-only escape hatches and intentional debugging.
    public static let isAvailable: Bool = {
        UserDefaults(suiteName: identifier) != nil
    }()

    /// Shared UserDefaults instance for cross-process config.
    ///
    /// In DEBUG builds a missing App Group is a hard `fatalError`: silently
    /// falling back to `.standard` desyncs the keyboard extension from the
    /// main App (the extension would write to one suite and the main App
    /// would read from another, or vice-versa) and the symptom is "I gave
    /// the App an API key and nothing happens" — which is exactly the bug
    /// this is meant to prevent.
    ///
    /// In release builds we keep the soft fallback + `NSLog` so an
    /// end-user whose developer account simply lacks the App Group still
    /// gets a usable main App (the keyboard extension won't work, but at
    /// least the App doesn't crash on launch).
    public static var defaults: UserDefaults {
        if let d = UserDefaults(suiteName: identifier) {
            return d
        }
        #if DEBUG
        fatalError("""
        ⚠️ App Group \(identifier) unavailable.

        Add the App Group in:
          1. Apple Developer portal → Identifiers → App Groups → add
             \(identifier)
          2. Both bundle IDs (main app + keyboard extension) → enable
             that App Group under Capabilities
          3. Re-generate the provisioning profile, download it, and
             re-run the project.

        Falling back to .standard would silently desync the keyboard
        extension from the main App — a hard crash in DEBUG is the
        only way to make the misconfiguration impossible to miss.
        """)
        #else
        NSLog("⚠️ [OSGKeyboard] App Group \(identifier) unavailable, falling back to .standard. The keyboard extension will not see config written by the main app.")
        return .standard
        #endif
    }
}
