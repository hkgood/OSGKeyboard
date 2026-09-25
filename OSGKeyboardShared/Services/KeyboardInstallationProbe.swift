// KeyboardInstallationProbe.swift
// OSGKeyboard · Shared
//
// Reports whether the keyboard extension is currently enabled in iOS
// Settings, without needing the extension to have run.
//
// `KeyboardSetupBridge` can only report what the extension observed the last
// time it launched. Removing the keyboard or revoking Full Access never
// launches it, so that record goes stale silently. This probe covers the
// "is the keyboard added" half of the question from the host side.

import Foundation

public enum KeyboardInstallationProbe {
    /// Bundle identifier of the keyboard extension.
    public static let keyboardExtensionBundleID = "com.osgkeyboard.ios.keyboard"

    /// `AppleKeyboards` lives in the global preferences domain, which every
    /// app's `UserDefaults` search list includes. It holds one entry per
    /// *enabled* keyboard — system layouts as locale strings, third-party
    /// keyboards as their extension bundle identifier.
    private static let enabledKeyboardsKey = "AppleKeyboards"

    /// Bundle identifiers / locale tags of every keyboard enabled in Settings,
    /// or `nil` when iOS does not expose the list to this process.
    public static func enabledKeyboardIdentifiers() -> [String]? {
        // Settings writes this list from another process while the app is
        // backgrounded. `UserDefaults` caches the global domain for the life of
        // the process, so a plain read keeps returning the pre-change value
        // until the app is relaunched — that is what makes the state look like
        // it needs several trips to Settings to settle. Going through
        // CFPreferences and synchronising first drops that cache.
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue(
            enabledKeyboardsKey as CFString,
            kCFPreferencesAnyApplication
        ) as? [String]
    }

    /// `true` / `false` when the list is readable, `nil` when it is not.
    ///
    /// The key is undocumented, so a missing list must degrade to "unknown"
    /// rather than "not installed" — callers should keep their extension-side
    /// verification as the source of truth and use this only to *contradict*
    /// a stale positive.
    public static func isKeyboardEnabled(
        bundleID: String = keyboardExtensionBundleID
    ) -> Bool? {
        isKeyboardEnabled(bundleID: bundleID, identifiers: enabledKeyboardIdentifiers())
    }

    /// Pure decision half, split out so tests can supply the list — including
    /// the `nil` "not exposed to this process" case, which a test `UserDefaults`
    /// cannot reproduce: its search list always includes the global domain the
    /// real `AppleKeyboards` value lives in.
    public static func isKeyboardEnabled(
        bundleID: String = keyboardExtensionBundleID,
        identifiers: [String]?
    ) -> Bool? {
        guard let identifiers else { return nil }
        return identifiers.contains(bundleID)
    }
}
