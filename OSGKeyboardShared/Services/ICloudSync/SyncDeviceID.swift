// SyncDeviceID.swift
// OSGKeyboard · Shared
//
// Stable per-install identifier for per-field / per-device iCloud merge.

import Foundation

public enum SyncDeviceID {
    private static let defaultsKey = "sync.deviceID.v1"

    /// Returns a stable device id stored in the active defaults suite.
    public static func current(defaults: UserDefaults = AppGroupStore().defaults) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}
