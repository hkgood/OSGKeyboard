// AppCloudSync.swift
// OSGKeyboard · Shared
//
// Single entry point for iCloud KVS sync in the main app: preferences
// toggles, settings payload, and personal dictionary.

import Foundation

@MainActor
public final class AppCloudSync {
    public static let shared = AppCloudSync()

    private let kvs: UbiquitousKeyValueStoreing
    private let makeStore: () -> AppGroupStore
    private let settingsSync: SettingsCloudSync
    private let dictionarySync: PersonalDictionaryCloudSync
    private var externalChangeObserver: NSObjectProtocol?

    public init(
        kvs: UbiquitousKeyValueStoreing = NSUbiquitousKeyValueStore.default,
        makeStore: @escaping () -> AppGroupStore = { AppGroupStore() },
        settingsSync: SettingsCloudSync? = nil,
        dictionarySync: PersonalDictionaryCloudSync? = nil
    ) {
        self.kvs = kvs
        self.makeStore = makeStore
        self.settingsSync = settingsSync ?? SettingsCloudSync(kvs: kvs, makeStore: makeStore)
        self.dictionarySync = dictionarySync ?? PersonalDictionaryCloudSync(kvs: kvs, makeStore: makeStore)
    }

    public func startObservingExternalChanges() {
        guard externalChangeObserver == nil else { return }
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pullAllIfEnabled()
            }
        }
    }

    public func stopObservingExternalChanges() {
        if let externalChangeObserver {
            NotificationCenter.default.removeObserver(externalChangeObserver)
            self.externalChangeObserver = nil
        }
    }

    /// Launch / foreground: refresh KVS toggles, then pull payloads.
    public func pullAllIfEnabled() async {
        let store = makeStore()
        ICloudSyncPreferences.migrateLegacyTogglesIfNeeded(kvs: kvs, store: store)

        let toggles = ICloudSyncPreferences.load(from: kvs, store: store)
        ICloudSyncPreferences.cacheToAppGroup(
            settingsEnabled: toggles.settings,
            dictionaryEnabled: toggles.dictionary,
            store: store
        )

        await settingsSync.pullAndMergeIfEnabled()
        await dictionarySync.pullAndMergeIfEnabled()
    }

    public var settingsSyncService: SettingsCloudSync { settingsSync }
    public var dictionarySyncService: PersonalDictionaryCloudSync { dictionarySync }
}
