// PolishStyleCloudSync.swift
// OSGKeyboard · Shared
//
// Mirrors user-created polish style packs through iCloud KVS. Built-in packs
// remain versioned app resources and are never uploaded.

import Foundation

public extension Notification.Name {
    static let polishStylesDidSyncFromCloud = Notification.Name(
        "com.osgkeyboard.polishStyles.didSyncFromCloud"
    )
}

public enum PolishStyleCloudSyncError: Error, Equatable, Sendable {
    case payloadTooLarge(byteCount: Int)
    case encodeFailed
    case decodeFailed
}

@MainActor
public final class PolishStyleCloudSync {
    public static let shared = PolishStyleCloudSync()
    public static let kvsKey = PolishStyleCatalog.kvsKeyV2
    /// Eight 6k-character prompts fit comfortably below this budget while
    /// preserving headroom in iCloud KVS's shared 1 MB quota.
    public static let maxPayloadBytes = 100_000

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
        let local = store.polishStyleCatalog
        guard let remote = loadRemote() else { return }
        let merged = PolishStyleCatalog.merge(local: local, remote: remote)
        guard merged != local else { return }
        store.setPolishStyleCatalog(merged)
        if !PolishStylePackCatalog.isValidActiveID(
            store.activePolishStyleId,
            userCatalog: merged
        ) {
            store.setActivePolishStyleId(PolishStylePackCatalog.defaultID)
        }
        NotificationCenter.default.post(name: .polishStylesDidSyncFromCloud, object: nil)
    }

    public func pushLocalIfEnabled(_ catalog: PolishStyleCatalog) async throws {
        let store = makeStore()
        guard store.settingsICloudSyncEnabled else { return }
        let merged = loadRemote().map {
            PolishStyleCatalog.merge(local: catalog, remote: $0)
        } ?? catalog
        if merged != catalog {
            store.setPolishStyleCatalog(merged)
        }
        try push(merged)
    }

    public func push(_ catalog: PolishStyleCatalog) throws {
        var payload = catalog
        payload.lastSyncedAt = Date()
        let data = try encode(payload)
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    public func loadRemote() -> PolishStyleCatalog? {
        guard let data = kvs.data(forKey: Self.kvsKey) else { return nil }
        return try? decode(data)
    }

    public func encode(_ catalog: PolishStyleCatalog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(catalog) else {
            throw PolishStyleCloudSyncError.encodeFailed
        }
        guard data.count <= Self.maxPayloadBytes else {
            throw PolishStyleCloudSyncError.payloadTooLarge(byteCount: data.count)
        }
        return data
    }

    public func decode(_ data: Data) throws -> PolishStyleCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let catalog = try? decoder.decode(PolishStyleCatalog.self, from: data) else {
            throw PolishStyleCloudSyncError.decodeFailed
        }
        return catalog
    }
}
