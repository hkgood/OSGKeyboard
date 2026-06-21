// KeyboardSetupBridge.swift
// OSGKeyboard · Shared
//
// The main app cannot query iOS for installed keyboards. The extension
// reports when it has appeared with Full Access so onboarding can skip
// the manual setup step for returning users.

import Foundation

public enum KeyboardSetupBridge {
    private enum Key {
        static let fullAccessReady = "keyboard.extension.fullAccessReady"
        static let lastSeenAt = "keyboard.extension.lastSeenAt"
    }

    /// True when the keyboard extension last appeared with Full Access enabled.
    public static var isReadyForOnboardingSkip: Bool {
        guard AppGroup.isAvailable else { return false }
        return AppGroup.defaults.bool(forKey: Key.fullAccessReady)
    }

    /// Called from the keyboard extension on each appearance.
    public static func markExtensionAppearance(hasFullAccess: Bool) {
        guard AppGroup.isAvailable else { return }
        let defaults = AppGroup.defaults
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastSeenAt)
        defaults.set(hasFullAccess, forKey: Key.fullAccessReady)
    }
}
