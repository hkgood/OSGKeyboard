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
        static let onboardingPracticeExpiresAt = "keyboard.onboarding.practiceExpiresAt"
        static let lastVoiceInsertionAt = "keyboard.extension.lastVoiceInsertionAt"
    }

    /// True when the keyboard extension last appeared with Full Access enabled.
    public static var isReadyForOnboardingSkip: Bool {
        guard AppGroup.isAvailable else { return false }
        return AppGroup.defaults.bool(forKey: Key.fullAccessReady)
    }

    /// True after the extension has appeared at least once. Unlike
    /// `isReadyForOnboardingSkip`, this also covers an appearance without Full
    /// Access so the host can explain the missing setting precisely.
    public static var hasAppeared: Bool {
        guard AppGroup.isAvailable else { return false }
        return AppGroup.defaults.double(forKey: Key.lastSeenAt) > 0
    }

    /// A short-lived exception that lets the real keyboard complete its first
    /// voice insertion while the host still owns the onboarding screen.
    public static var isOnboardingPracticeActive: Bool {
        onboardingPracticeIsActive()
    }

    /// Wall clock of the most recent voice insertion issued by the extension.
    /// The host compares this with the current practice start time, so an old
    /// insertion can never complete a new onboarding run.
    public static var lastVoiceInsertionAt: Date? {
        guard AppGroup.isAvailable else { return nil }
        let value = AppGroup.defaults.double(forKey: Key.lastVoiceInsertionAt)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public static func onboardingPracticeIsActive(
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return false }
        return store.double(forKey: Key.onboardingPracticeExpiresAt) > now.timeIntervalSince1970
    }

    public static func setOnboardingPracticeActive(
        _ active: Bool,
        duration: TimeInterval = 30 * 60,
        defaults: UserDefaults? = nil,
        now: Date = Date()
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        if active {
            store.set(
                now.addingTimeInterval(duration).timeIntervalSince1970,
                forKey: Key.onboardingPracticeExpiresAt
            )
        } else {
            store.removeObject(forKey: Key.onboardingPracticeExpiresAt)
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    /// Called from the keyboard extension on each appearance.
    public static func markExtensionAppearance(hasFullAccess: Bool) {
        guard AppGroup.isAvailable else { return }
        let defaults = AppGroup.defaults
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastSeenAt)
        defaults.set(hasFullAccess, forKey: Key.fullAccessReady)
        AppGroupConfigDarwin.postConfigChanged()
    }

    /// Called only after a Flow transcript has been inserted into the host
    /// field, not when recognition merely produced a result.
    public static func markVoiceInsertion() {
        guard AppGroup.isAvailable else { return }
        AppGroup.defaults.set(
            Date().timeIntervalSince1970,
            forKey: Key.lastVoiceInsertionAt
        )
        AppGroupConfigDarwin.postConfigChanged()
    }
}
