// ICloudSyncPreferences.swift
// OSGKeyboard · Shared
//
// iCloud KVS is the source of truth for cross-device sync toggles
// (scheme A). App Group UserDefaults keeps a local cache so the
// keyboard extension and offline UI can read the last-known state.

import Foundation

public enum ICloudSyncPreferences {
    public static let settingsEnabledKey = "iCloudSync.settingsEnabled"
    public static let dictionaryEnabledKey = "personalDictionary.syncEnabled"

    /// Read sync toggles from KVS, falling back to the App Group cache
    /// when a key has not been uploaded yet.
    public static func load(from kvs: UbiquitousKeyValueStoreing, store: AppGroupStore) -> (settings: Bool, dictionary: Bool) {
        let settings = kvs.object(forKey: settingsEnabledKey) as? Bool
            ?? store.settingsICloudSyncEnabled
        let dictionary = kvs.object(forKey: dictionaryEnabledKey) as? Bool
            ?? store.personalDictionaryICloudSyncEnabled
        return (settings, dictionary)
    }

    /// Mirror KVS toggles into the App Group cache.
    public static func cacheToAppGroup(
        settingsEnabled: Bool,
        dictionaryEnabled: Bool,
        store: AppGroupStore
    ) {
        store.setSettingsICloudSyncEnabled(settingsEnabled)
        store.setPersonalDictionaryICloudSyncEnabled(dictionaryEnabled)
    }

    public static func pushSettingsEnabled(_ enabled: Bool, kvs: UbiquitousKeyValueStoreing) {
        kvs.set(enabled, forKey: settingsEnabledKey)
        _ = kvs.synchronize()
    }

    public static func pushDictionaryEnabled(_ enabled: Bool, kvs: UbiquitousKeyValueStoreing) {
        kvs.set(enabled, forKey: dictionaryEnabledKey)
        _ = kvs.synchronize()
    }

    /// One-time migration: upload locally cached toggles when KVS has no value yet.
    public static func migrateLegacyTogglesIfNeeded(kvs: UbiquitousKeyValueStoreing, store: AppGroupStore) {
        if kvs.object(forKey: dictionaryEnabledKey) == nil {
            pushDictionaryEnabled(store.personalDictionaryICloudSyncEnabled, kvs: kvs)
        }
        if kvs.object(forKey: settingsEnabledKey) == nil {
            pushSettingsEnabled(store.settingsICloudSyncEnabled, kvs: kvs)
        }
    }
}
