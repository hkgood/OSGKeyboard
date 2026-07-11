// SettingsCloudSync.swift
// OSGKeyboard · Shared
//
// Mirrors user-facing app settings through iCloud KVS (`appSettings.v2`)
// with per-field merge. API keys sync via iCloud Keychain — never KVS.

import Foundation

public extension Notification.Name {
    /// Posted after remote settings are applied to the App Group cache.
    static let settingsDidSyncFromCloud = Notification.Name(
        "com.osgkeyboard.settings.didSyncFromCloud"
    )
}

public enum SettingsCloudSyncError: Error, Equatable, Sendable {
    case encodeFailed
    case decodeFailed
}

@MainActor
public final class SettingsCloudSync {
    public static let shared = SettingsCloudSync()

    public static let kvsKey = SyncedAppSettingsV2.kvsKey
    public static let legacyKVSKey = SyncedAppSettings.legacyKVSKey

    private let kvs: UbiquitousKeyValueStoreing
    private let makeStore: () -> AppGroupStore
    private let historyDefaults: () -> UserDefaults

    public init(
        kvs: UbiquitousKeyValueStoreing = NSUbiquitousKeyValueStore.default,
        makeStore: @escaping () -> AppGroupStore = { AppGroupStore() },
        historyDefaults: @escaping () -> UserDefaults = { .standard }
    ) {
        self.kvs = kvs
        self.makeStore = makeStore
        self.historyDefaults = historyDefaults
    }

    public func pullAndMergeIfEnabled() async {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }
        await pullAndMerge(store: store)
    }

    public func pushLocalIfEnabled() async throws {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }
        let deviceID = SyncDeviceID.current(defaults: store.defaults)
        let config = store.configurationSnapshot()
        var local = loadLocalPayload(from: store.defaults, configuration: config, deviceID: deviceID)
        local = local.patchLocalChanges(from: config, deviceID: deviceID)
        saveLocalPayload(local, to: store.defaults)

        let remote = loadRemote()
        let toPush = remote.map { SyncedAppSettingsV2.merge(local: local, remote: $0) } ?? local
        try push(toPush)
    }

    public func enableSync() async throws {
        let store = makeStore()
        ICloudSyncPreferences.pushSettingsEnabled(true, kvs: kvs)
        ICloudSyncPreferences.pushDictionaryEnabled(true, kvs: kvs)
        ICloudSyncPreferences.cacheToAppGroup(
            settingsEnabled: true,
            dictionaryEnabled: true,
            store: store
        )

        Keychain.migrateLocalKeysToICloud()

        let deviceID = SyncDeviceID.current(defaults: store.defaults)
        let config = store.configurationSnapshot()
        var local = loadLocalPayload(from: store.defaults, configuration: config, deviceID: deviceID)
        local = local.patchLocalChanges(from: config, deviceID: deviceID)
        let remote = loadRemote() ?? local
        let merged = SyncedAppSettingsV2.merge(local: local, remote: remote)
        apply(merged, to: store, postNotification: false)
        try push(merged)

        NotificationCenter.default.post(name: .settingsDidSyncFromCloud, object: nil)
        let statisticsSync = UsageStatisticsCloudSync(kvs: kvs, makeStore: makeStore)
        try await statisticsSync.mergeAndPushIfEnabled()
        let historySync = SpeechHistoryCloudSync(
            kvs: kvs,
            makeStore: makeStore,
            historyDefaults: historyDefaults
        )
        try await historySync.mergeAndPushIfEnabled()
    }

    public func disableSync() {
        let store = makeStore()
        ICloudSyncPreferences.pushSettingsEnabled(false, kvs: kvs)
        ICloudSyncPreferences.pushDictionaryEnabled(false, kvs: kvs)
        store.setSettingsICloudSyncEnabled(false)
        store.setPersonalDictionaryICloudSyncEnabled(false)
    }

    public func pullAndMerge(store: AppGroupStore) async {
        guard store.settingsICloudSyncEnabled else { return }
        guard let remote = loadRemote() else { return }

        let deviceID = SyncDeviceID.current(defaults: store.defaults)
        let config = store.configurationSnapshot()
        var local = loadLocalPayload(from: store.defaults, configuration: config, deviceID: deviceID)
        local = local.patchLocalChanges(from: config, deviceID: deviceID)
        let merged = SyncedAppSettingsV2.merge(local: local, remote: remote)
        var trial = config
        merged.applying(to: &trial)
        guard trial != config else { return }

        apply(merged, to: store, postNotification: true)
    }

    public func push(_ settings: SyncedAppSettingsV2) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(settings) else {
            throw SettingsCloudSyncError.encodeFailed
        }
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    public func loadRemote() -> SyncedAppSettingsV2? {
        if let data = kvs.data(forKey: Self.kvsKey) {
            return try? decodeV2(data)
        }
        guard let legacyData = kvs.data(forKey: Self.legacyKVSKey),
              let legacy = try? decodeLegacy(legacyData) else {
            return nil
        }
        let deviceID = SyncDeviceID.current()
        return SyncedAppSettingsV2.migrated(from: legacy, deviceID: deviceID)
    }

    public func decodeV2(_ data: Data) throws -> SyncedAppSettingsV2 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let settings = try? decoder.decode(SyncedAppSettingsV2.self, from: data) else {
            throw SettingsCloudSyncError.decodeFailed
        }
        return settings
    }

    public func decodeLegacy(_ data: Data) throws -> SyncedAppSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let settings = try? decoder.decode(SyncedAppSettings.self, from: data) else {
            throw SettingsCloudSyncError.decodeFailed
        }
        return settings
    }

    private func apply(
        _ settings: SyncedAppSettingsV2,
        to store: AppGroupStore,
        postNotification: Bool
    ) {
        var config = store.configurationSnapshot()
        settings.applying(to: &config)
        store.saveConfiguration(config, settingsCloudUpdatedAt: settings.latestUpdatedAt)
        saveLocalPayload(settings, to: store.defaults)
        if postNotification {
            AppGroupConfigDarwin.postConfigChanged()
            NotificationCenter.default.post(name: .settingsDidSyncFromCloud, object: nil)
        }
    }

    private func loadLocalPayload(
        from defaults: UserDefaults,
        configuration: AppGroupConfiguration,
        deviceID: String
    ) -> SyncedAppSettingsV2 {
        if let data = defaults.data(forKey: AppGroupConfiguration.Keys.settingsCloudPayloadV2),
           let payload = try? JSONDecoder().decode(SyncedAppSettingsV2.self, from: data) {
            return payload
        }
        let stamp = defaults.object(forKey: AppGroupConfiguration.Keys.settingsCloudUpdatedAt) as? TimeInterval
        let updatedAt = stamp.map { Date(timeIntervalSince1970: $0) } ?? .distantPast
        return SyncedAppSettingsV2.seeded(
            from: configuration,
            deviceID: deviceID,
            updatedAt: updatedAt
        )
    }

    private func saveLocalPayload(_ payload: SyncedAppSettingsV2, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: AppGroupConfiguration.Keys.settingsCloudPayloadV2)
    }
}

private extension AppGroupStore {
    func configurationSnapshot() -> AppGroupConfiguration {
        AppGroupConfiguration.load(fromAvailable: defaults)
    }

    func saveConfiguration(_ configuration: AppGroupConfiguration, settingsCloudUpdatedAt: Date) {
        let config = configuration
        config.save(to: defaults)
        defaults.set(
            settingsCloudUpdatedAt.timeIntervalSince1970,
            forKey: AppGroupConfiguration.Keys.settingsCloudUpdatedAt
        )
    }
}
