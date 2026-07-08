// SpeechHistoryCloudSync.swift
// OSGKeyboard · Shared
//
// Mirrors speech history through iCloud KVS when settings sync is enabled.

import Foundation

public extension Notification.Name {
    /// Posted after remote speech history is applied locally.
    static let speechHistoryDidSyncFromCloud = Notification.Name(
        "com.osgkeyboard.speechHistory.didSyncFromCloud"
    )
}

public enum SpeechHistoryCloudSyncError: Error, Equatable, Sendable {
    case payloadTooLarge(byteCount: Int)
    case encodeFailed
    case decodeFailed
}

@MainActor
public final class SpeechHistoryCloudSync {
    public static let shared = SpeechHistoryCloudSync()

    public static let kvsKey = SyncedSpeechHistory.kvsKey
    public static let legacyKVSKey = SyncedSpeechHistory.legacyKVSKey
    /// Stay below the ~1 MB per-key KVS limit.
    public static let maxPayloadBytes = 900_000

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
        let local = SpeechHistoryStorage.load(from: historyDefaults())
        try push(local)
    }

    /// Called when settings sync is first enabled to union local + remote history.
    public func mergeAndPushIfEnabled() async throws {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }

        let defaults = historyDefaults()
        let local = SpeechHistoryStorage.load(from: defaults)
        let remote = loadRemote() ?? local
        let merged = SyncedSpeechHistory.merge(local: local, remote: remote)
        apply(merged, to: defaults, postNotification: false)
        try push(merged)
        NotificationCenter.default.post(name: .speechHistoryDidSyncFromCloud, object: nil)
    }

    public func pullAndMerge(store: AppGroupStore) async {
        guard store.settingsICloudSyncEnabled else { return }
        guard let remote = loadRemote() else { return }

        let defaults = historyDefaults()
        let local = SpeechHistoryStorage.load(from: defaults)
        let merged = SyncedSpeechHistory.merge(local: local, remote: remote)
        guard merged != local else { return }

        apply(merged, to: defaults, postNotification: true)
    }

    public func push(_ history: SyncedSpeechHistory) throws {
        let data = try encode(history)
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    public func loadRemote() -> SyncedSpeechHistory? {
        if let data = kvs.data(forKey: Self.kvsKey) {
            return try? decode(data)
        }
        guard let legacyData = kvs.data(forKey: Self.legacyKVSKey) else { return nil }
        return try? decode(legacyData)
    }

    public func encode(_ history: SyncedSpeechHistory) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else {
            throw SpeechHistoryCloudSyncError.encodeFailed
        }
        guard data.count <= Self.maxPayloadBytes else {
            throw SpeechHistoryCloudSyncError.payloadTooLarge(byteCount: data.count)
        }
        return data
    }

    public func decode(_ data: Data) throws -> SyncedSpeechHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let history = try? decoder.decode(SyncedSpeechHistory.self, from: data) else {
            throw SpeechHistoryCloudSyncError.decodeFailed
        }
        return history
    }

    private func apply(
        _ history: SyncedSpeechHistory,
        to defaults: UserDefaults,
        postNotification: Bool
    ) {
        SpeechHistoryStorage.save(history, to: defaults)
        if postNotification {
            NotificationCenter.default.post(name: .speechHistoryDidSyncFromCloud, object: nil)
        }
    }
}
