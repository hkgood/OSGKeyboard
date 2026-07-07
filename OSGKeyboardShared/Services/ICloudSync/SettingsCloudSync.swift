// SettingsCloudSync.swift
// OSGKeyboard · Shared
//
// Mirrors user-facing app settings through iCloud KVS. API keys stay
// in Keychain and are never uploaded.

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

    public static let kvsKey = "appSettings.v1"

    private let kvs: UbiquitousKeyValueStoreing
    private let makeStore: () -> AppGroupStore

    public init(
        kvs: UbiquitousKeyValueStoreing = NSUbiquitousKeyValueStore.default,
        makeStore: @escaping () -> AppGroupStore = { AppGroupStore() }
    ) {
        self.kvs = kvs
        self.makeStore = makeStore
    }

    public func pullAndMergeIfEnabled() async {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }
        await pullAndMerge(store: store)
    }

    public func pushLocalIfEnabled() async throws {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }
        let local = SyncedAppSettings.from(configuration: store.configurationSnapshot())
        try push(local)
    }

    public func enableSync() async throws {
        let store = makeStore()
        ICloudSyncPreferences.pushSettingsEnabled(true, kvs: kvs)
        ICloudSyncPreferences.cacheToAppGroup(
            settingsEnabled: true,
            dictionaryEnabled: store.personalDictionaryICloudSyncEnabled,
            store: store
        )

        let local = SyncedAppSettings.from(configuration: store.configurationSnapshot())
        let remote = loadRemote() ?? local
        let merged = SyncedAppSettings.merge(local: local, remote: remote)
        apply(merged, to: store, postNotification: false)
        try push(merged)
        NotificationCenter.default.post(name: .settingsDidSyncFromCloud, object: nil)
    }

    public func disableSync() {
        let store = makeStore()
        ICloudSyncPreferences.pushSettingsEnabled(false, kvs: kvs)
        store.setSettingsICloudSyncEnabled(false)
    }

    public func pullAndMerge(store: AppGroupStore) async {
        guard store.settingsICloudSyncEnabled else { return }
        guard let remote = loadRemote() else { return }

        let local = SyncedAppSettings.from(
            configuration: store.configurationSnapshot(),
            updatedAt: store.settingsCloudUpdatedAt ?? .distantPast
        )
        let merged = SyncedAppSettings.merge(local: local, remote: remote)
        guard merged != local else { return }

        apply(merged, to: store, postNotification: true)
    }

    public func push(_ settings: SyncedAppSettings) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(settings) else {
            throw SettingsCloudSyncError.encodeFailed
        }
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    public func loadRemote() -> SyncedAppSettings? {
        guard let data = kvs.data(forKey: Self.kvsKey) else { return nil }
        return try? decode(data)
    }

    public func decode(_ data: Data) throws -> SyncedAppSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let settings = try? decoder.decode(SyncedAppSettings.self, from: data) else {
            throw SettingsCloudSyncError.decodeFailed
        }
        return settings
    }

    private func apply(
        _ settings: SyncedAppSettings,
        to store: AppGroupStore,
        postNotification: Bool
    ) {
        var config = store.configurationSnapshot()
        settings.applying(to: &config)
        store.saveConfiguration(config, settingsCloudUpdatedAt: settings.updatedAt)
        if postNotification {
            AppGroupConfigDarwin.postConfigChanged()
            NotificationCenter.default.post(name: .settingsDidSyncFromCloud, object: nil)
        }
    }
}

private extension AppGroupStore {
    func configurationSnapshot() -> AppGroupConfiguration {
        AppGroupConfiguration.load(fromAvailable: defaults)
    }

    func saveConfiguration(_ configuration: AppGroupConfiguration, settingsCloudUpdatedAt: Date) {
        let config = configuration
        config.save(to: defaults)
        defaults.set(settingsCloudUpdatedAt.timeIntervalSince1970, forKey: AppGroupConfiguration.Keys.settingsCloudUpdatedAt)
    }
}
