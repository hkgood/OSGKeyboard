// AppCloudSync.swift
// OSGKeyboard · Shared
//
// Single entry point for iCloud KVS sync in the main app: preferences
// toggles, usage statistics, settings payload, speech history, and
// personal dictionary.

import Foundation

@MainActor
public final class AppCloudSync {
    public static let shared = AppCloudSync()

    private let kvs: UbiquitousKeyValueStoreing
    private let makeStore: () -> AppGroupStore
    private let settingsSync: SettingsCloudSync
    private let dictionarySync: PersonalDictionaryCloudSync
    private let usageStatisticsSync: UsageStatisticsCloudSync
    private let speechHistorySync: SpeechHistoryCloudSync
    private var externalChangeObserver: NSObjectProtocol?

    public init(
        kvs: UbiquitousKeyValueStoreing = NSUbiquitousKeyValueStore.default,
        makeStore: @escaping () -> AppGroupStore = { AppGroupStore() },
        historyDefaults: @escaping () -> UserDefaults = { .standard },
        settingsSync: SettingsCloudSync? = nil,
        dictionarySync: PersonalDictionaryCloudSync? = nil,
        usageStatisticsSync: UsageStatisticsCloudSync? = nil,
        speechHistorySync: SpeechHistoryCloudSync? = nil
    ) {
        self.kvs = kvs
        self.makeStore = makeStore
        self.settingsSync = settingsSync
            ?? SettingsCloudSync(kvs: kvs, makeStore: makeStore, historyDefaults: historyDefaults)
        self.dictionarySync = dictionarySync ?? PersonalDictionaryCloudSync(kvs: kvs, makeStore: makeStore)
        self.usageStatisticsSync = usageStatisticsSync
            ?? UsageStatisticsCloudSync(kvs: kvs, makeStore: makeStore)
        self.speechHistorySync = speechHistorySync
            ?? SpeechHistoryCloudSync(kvs: kvs, makeStore: makeStore, historyDefaults: historyDefaults)
    }

    /// Serializes external-change pulls: KVS posts change notifications in
    /// bursts (one per key at times), and overlapping pull-merge-apply runs
    /// can interleave their read/write phases. `wantsAnotherPull` coalesces
    /// every burst into at most one trailing re-pull.
    private var isPulling = false
    private var wantsAnotherPull = false

    public func startObservingExternalChanges() {
        guard externalChangeObserver == nil else { return }
        externalChangeObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            // Distinguish WHY the store changed. `.accountChange` means the
            // user switched iCloud accounts — the incoming values belong to a
            // DIFFERENT account and must not be merged into this one's data
            // (deleted-entry resurrection, foreign history, wrong settings).
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            if reason == NSUbiquitousKeyValueStoreAccountChange {
                return
            }
            Task { @MainActor in
                await self.pullAllCoalesced()
            }
        }
    }

    private func pullAllCoalesced() async {
        guard !isPulling else {
            wantsAnotherPull = true
            return
        }
        isPulling = true
        defer { isPulling = false }
        repeat {
            wantsAnotherPull = false
            await pullAllIfEnabled()
        } while wantsAnotherPull
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
        await usageStatisticsSync.pullAndMergeIfEnabled()
        await speechHistorySync.pullAndMergeIfEnabled()
        await dictionarySync.pullAndMergeIfEnabled()
    }

    /// Low-risk manual sync: pull remote changes, merge, then push local state.
    /// Each push runs independently — one payload failing must not abort the
    /// others (a too-large history would otherwise also kill the dictionary
    /// push). The first error is rethrown after every push has been tried.
    public func syncNow() async throws {
        let store = makeStore()
        await pullAllIfEnabled()

        var firstError: Error?
        func attempt(_ body: () async throws -> Void) async {
            do { try await body() } catch { if firstError == nil { firstError = error } }
        }

        if store.settingsICloudSyncEnabled {
            await attempt { try await settingsSync.pushLocalIfEnabled() }
            await attempt { try await usageStatisticsSync.pushLocalIfEnabled() }
            await attempt { try await speechHistorySync.pushLocalIfEnabled() }
        }
        if store.personalDictionaryICloudSyncEnabled {
            await attempt { try await dictionarySync.pushLocalIfEnabled(store.personalDictionary) }
        }
        if let firstError { throw firstError }
    }

    public var settingsSyncService: SettingsCloudSync { settingsSync }
    public var dictionarySyncService: PersonalDictionaryCloudSync { dictionarySync }
    public var usageStatisticsSyncService: UsageStatisticsCloudSync { usageStatisticsSync }
    public var speechHistorySyncService: SpeechHistoryCloudSync { speechHistorySync }
}
