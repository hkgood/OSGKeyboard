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
    /// The 1 MB iCloud KVS quota is for the WHOLE store, not per key.
    /// History and the personal dictionary must fit together (plus settings
    /// and usage stats) — once the store exceeds 1 MB, KVS rejects writes
    /// for ALL keys with `QuotaViolation` and every sync silently stops.
    /// Budget: ~400 KB history + ~400 KB dictionary + headroom for the rest.
    public static let maxPayloadBytes = 400_000

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
        // Read-merge-write: pushing the local view verbatim would overwrite
        // entries another device added since our last pull (KVS is
        // last-writer-wins with no server-side merge).
        let defaults = historyDefaults()
        let local = SpeechHistoryStorage.load(from: defaults)
        let merged = loadRemote().map { SyncedSpeechHistory.merge(local: local, remote: $0) } ?? local
        if merged != local {
            apply(merged, to: defaults, postNotification: true)
        }
        try push(merged)
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
        let data = try encodeFittingBudget(history)
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    /// Encode, dropping the oldest entries until the payload fits the KVS
    /// budget. Without this, a history that once fit under the old 900 KB
    /// cap (300 long dictations easily exceed 400 KB) would make EVERY push
    /// throw forever — automatic pushes are fire-and-forget, so sync would
    /// just silently die with no way back short of clearing all history.
    /// Only the *uploaded* copy is trimmed; local history keeps its full
    /// 300 entries.
    func encodeFittingBudget(_ history: SyncedSpeechHistory) throws -> Data {
        var payload = history
        while true {
            do {
                return try encode(payload)
            } catch SpeechHistoryCloudSyncError.payloadTooLarge {
                guard payload.entries.count > 1 else { throw SpeechHistoryCloudSyncError.payloadTooLarge(byteCount: 0) }
                // Drop the oldest ~10% per pass; entries are kept
                // newest-first by the store, so trim from the tail.
                let sorted = payload.entries.sorted { $0.createdAt > $1.createdAt }
                let keep = max(1, sorted.count - max(1, sorted.count / 10))
                payload.entries = Array(sorted.prefix(keep))
            }
        }
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
