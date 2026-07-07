// PersonalDictionaryCloudSync.swift
// OSGKeyboard · Shared
//
// Mirrors the personal dictionary through iCloud Key-Value Store while
// keeping App Group UserDefaults as the keyboard extension's runtime
// source of truth. Intended for main-app call sites only.

import Foundation

public extension Notification.Name {
    /// Posted after a remote KVS pull updates the App Group dictionary.
    static let personalDictionaryDidSyncFromCloud = Notification.Name(
        "com.osgkeyboard.personalDictionary.didSyncFromCloud"
    )
}

public enum PersonalDictionaryCloudSyncError: Error, Equatable, Sendable {
    case payloadTooLarge(byteCount: Int)
    case encodeFailed
    case decodeFailed
}

@MainActor
public final class PersonalDictionaryCloudSync {
    public static let shared = PersonalDictionaryCloudSync()

    public static let kvsKey = "personalDictionary.v1"
    /// Stay below the ~1 MB per-key KVS limit.
    public static let maxPayloadBytes = 900_000

    private let kvs: UbiquitousKeyValueStoreing
    private let makeStore: () -> AppGroupStore
    private var externalChangeObserver: NSObjectProtocol?

    public init(
        kvs: UbiquitousKeyValueStoreing = NSUbiquitousKeyValueStore.default,
        makeStore: @escaping () -> AppGroupStore = { AppGroupStore() }
    ) {
        self.kvs = kvs
        self.makeStore = makeStore
    }

    // MARK: - Lifecycle

    public func startObservingExternalChanges() {
        guard externalChangeObserver == nil else { return }
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pullAndMergeIfEnabled()
            }
        }
    }

    public func stopObservingExternalChanges() {
        if let externalChangeObserver {
            NotificationCenter.default.removeObserver(externalChangeObserver)
            self.externalChangeObserver = nil
        }
    }

    /// Pull remote changes on launch / foreground when sync is enabled.
    public func pullAndMergeIfEnabled() async {
        let store = makeStore()
        guard store.personalDictionaryICloudSyncEnabled else { return }
        await pullAndMerge(store: store)
    }

    /// Push the current local dictionary when sync is enabled.
    public func pushLocalIfEnabled(_ dictionary: PersonalDictionary) async throws {
        let store = makeStore()
        guard store.personalDictionaryICloudSyncEnabled else { return }
        try push(dictionary)
    }

    /// Enable sync: merge local + remote, persist locally, then upload.
    public func enableSync() async throws {
        let store = makeStore()
        ICloudSyncPreferences.pushDictionaryEnabled(true, kvs: kvs)
        ICloudSyncPreferences.cacheToAppGroup(
            settingsEnabled: store.settingsICloudSyncEnabled,
            dictionaryEnabled: true,
            store: store
        )

        let local = store.personalDictionary
        let remote = loadRemote() ?? .empty
        let merged = PersonalDictionary.merge(local: local, remote: remote)
        store.setPersonalDictionary(merged)
        try push(merged)
    }

    public func disableSync() {
        let store = makeStore()
        ICloudSyncPreferences.pushDictionaryEnabled(false, kvs: kvs)
        store.setPersonalDictionaryICloudSyncEnabled(false)
    }

    // MARK: - Core operations

    public func pullAndMerge(store: AppGroupStore) async {
        guard store.personalDictionaryICloudSyncEnabled else { return }

        let local = store.personalDictionary
        guard let remote = loadRemote() else { return }

        let merged = PersonalDictionary.merge(local: local, remote: remote)
        guard merged != local else { return }

        store.setPersonalDictionary(merged)
        NotificationCenter.default.post(name: .personalDictionaryDidSyncFromCloud, object: nil)
    }

    public func push(_ dictionary: PersonalDictionary) throws {
        var payload = dictionary
        payload.lastSyncedAt = Date()
        let data = try encode(payload)
        kvs.set(data, forKey: Self.kvsKey)
        _ = kvs.synchronize()
    }

    public func loadRemote() -> PersonalDictionary? {
        guard let data = kvs.data(forKey: Self.kvsKey) else { return nil }
        return try? decode(data)
    }

    // MARK: - Encoding

    public func encode(_ dictionary: PersonalDictionary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(dictionary) else {
            throw PersonalDictionaryCloudSyncError.encodeFailed
        }
        guard data.count <= Self.maxPayloadBytes else {
            throw PersonalDictionaryCloudSyncError.payloadTooLarge(byteCount: data.count)
        }
        return data
    }

    public func decode(_ data: Data) throws -> PersonalDictionary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let dictionary = try? decoder.decode(PersonalDictionary.self, from: data) else {
            throw PersonalDictionaryCloudSyncError.decodeFailed
        }
        return dictionary
    }
}
