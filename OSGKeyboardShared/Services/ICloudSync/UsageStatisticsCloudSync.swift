// UsageStatisticsCloudSync.swift
// OSGKeyboard · Shared
//
// Mirrors cumulative usage statistics through iCloud KVS (`usageStatistics.v2`)
// using per-device G-Counter merge when settings sync is enabled.

import Foundation

public extension Notification.Name {
    /// Posted after remote usage statistics are applied locally.
    static let usageStatisticsDidSyncFromCloud = Notification.Name(
        "com.osgkeyboard.usageStatistics.didSyncFromCloud"
    )
}

public enum UsageStatisticsCloudSyncError: Error, Equatable, Sendable {
    case encodeFailed
    case decodeFailed
}

@MainActor
public final class UsageStatisticsCloudSync {
    public static let shared = UsageStatisticsCloudSync()

    public static let kvsKey = SyncedUsageStatisticsV2.kvsKey
    public static let legacyKVSKey = SyncedUsageStatisticsStorage.legacyStorageKey

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
        let local = SyncedUsageStatisticsStorage.load(from: store.defaults)
        try push(local)
    }

    /// Called when settings sync is first enabled to union local + remote totals.
    public func mergeAndPushIfEnabled() async throws {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }

        let local = SyncedUsageStatisticsStorage.load(from: store.defaults)
        let remote = loadRemote() ?? local
        let merged = SyncedUsageStatisticsV2.merge(local: local, remote: remote)
        apply(merged, to: store.defaults, postNotification: false)
        try push(merged)
        NotificationCenter.default.post(name: .usageStatisticsDidSyncFromCloud, object: nil)
    }

    public func pullAndMerge(store: AppGroupStore) async {
        guard store.settingsICloudSyncEnabled else { return }
        guard let remote = loadRemote() else { return }

        let local = SyncedUsageStatisticsStorage.load(from: store.defaults)
        let merged = SyncedUsageStatisticsV2.merge(local: local, remote: remote)
        guard merged != local else { return }

        apply(merged, to: store.defaults, postNotification: true)
    }

    public func push(_ stats: SyncedUsageStatisticsV2) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(stats) else {
            throw UsageStatisticsCloudSyncError.encodeFailed
        }
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    /// Removes the cumulative-stats payload from iCloud KVS. Used by the
    /// one-time cleanup that clears data corrupted by the pre-fix
    /// double-counting bug so it can't be pulled back onto other devices.
    public func purgeRemote() {
        kvs.set(Data?.none, forKey: Self.kvsKey)
        kvs.set(Data?.none, forKey: Self.legacyKVSKey)
        _ = kvs.synchronize()
    }

    public func loadRemote() -> SyncedUsageStatisticsV2? {
        if let data = kvs.data(forKey: Self.kvsKey) {
            return try? decodeV2(data)
        }
        guard let legacyData = kvs.data(forKey: Self.legacyKVSKey) else { return nil }
        let deviceID = SyncDeviceID.current()
        guard let legacy = try? decodeLegacy(legacyData) else { return nil }
        return SyncedUsageStatisticsV2.migrated(from: legacy, deviceID: deviceID)
    }

    public func decodeV2(_ data: Data) throws -> SyncedUsageStatisticsV2 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stats = try? decoder.decode(SyncedUsageStatisticsV2.self, from: data) else {
            throw UsageStatisticsCloudSyncError.decodeFailed
        }
        return stats
    }

    public func decodeLegacy(_ data: Data) throws -> UsageStatistics {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stats = try? decoder.decode(UsageStatistics.self, from: data) else {
            throw UsageStatisticsCloudSyncError.decodeFailed
        }
        return stats
    }

    private func apply(
        _ stats: SyncedUsageStatisticsV2,
        to defaults: UserDefaults,
        postNotification: Bool
    ) {
        SyncedUsageStatisticsStorage.save(stats, to: defaults)
        if postNotification {
            NotificationCenter.default.post(name: .usageStatisticsDidSyncFromCloud, object: nil)
        }
    }
}
