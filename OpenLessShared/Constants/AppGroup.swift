// AppGroup.swift
// OSGKeyboard · Shared
//
// App Group identifier shared between main app and keyboard extension.
// UserDefaults(suiteName:) and file containers use this.

import Foundation

public enum AppGroup {
    /// App Group container identifier (must match entitlements in both targets)
    public static let identifier = "group.com.osgkeyboard.ios"

    /// Shared UserDefaults instance for cross-process config
    public static var defaults: UserDefaults {
        guard let d = UserDefaults(suiteName: identifier) else {
            assertionFailure("App Group \(identifier) not configured in entitlements")
            return .standard
        }
        return d
    }
}
