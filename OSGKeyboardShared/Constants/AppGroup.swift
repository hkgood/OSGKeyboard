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
    /// Checks both `UserDefaults(suiteName:)` *and* the on-disk container.
    /// The suite alone can appear to open while the container is still `(null)`
    /// when provisioning is misconfigured — that case produces the
    /// `CFPrefsPlistSource … Container: (null)` console warning.
    public static let isAvailable: Bool = {
        guard UserDefaults(suiteName: identifier) != nil else { return false }
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) != nil
    }()

    /// Shared UserDefaults when the App Group suite is available; `nil` otherwise.
    ///
    /// Prefer this in Release builds and in the keyboard extension so callers
    /// can surface a setup error instead of silently reading/writing the wrong suite.
    public static var defaultsIfAvailable: UserDefaults? {
        guard isAvailable else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    /// Shared UserDefaults instance for cross-process config.
    ///
    /// In DEBUG builds a missing App Group is a hard `fatalError`: silently
    /// falling back to `.standard` desyncs the keyboard extension from the
    /// main App (the extension would write to one suite and the main App
    /// would read from another, or vice-versa) and the symptom is "I gave
    /// the App an API key and nothing happens" — which is exactly the bug
    /// this is meant to prevent.
    ///
    /// In Release builds there is **no** `.standard` fallback — use
    /// `defaultsIfAvailable` and handle `nil` when provisioning is missing.
    public static var defaults: UserDefaults {
        guard let suite = defaultsIfAvailable else {
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
            fatalError("App Group \(identifier) unavailable. Check entitlements and provisioning.")
            #endif
        }
        return suite
    }
}
