// SpeechHistoryCloudSyncTests.swift
// OSGKeyboardTests
//
// Hermetic tests for speech history iCloud merge, tombstones, and caps.

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class SpeechHistoryCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var configDefaults: UserDefaults!
    private var historyDefaults: UserDefaults!
    private var store: AppGroupStore!
    private var kvs: FakeUbiquitousKeyValueStore!
    private var sync: SpeechHistoryCloudSync!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.history.\(UUID().uuidString)"
        configDefaults = UserDefaults(suiteName: suiteName)!
        configDefaults.removePersistentDomain(forName: suiteName)
        historyDefaults = UserDefaults(suiteName: "\(suiteName).history")!
        historyDefaults.removePersistentDomain(forName: "\(suiteName).history")
        store = AppGroupStore(defaults: configDefaults)
        store.setSettingsICloudSyncEnabled(true)
        kvs = FakeUbiquitousKeyValueStore()
        sync = SpeechHistoryCloudSync(kvs: kvs, makeStore: { [unowned self] in store }) { [unowned self] in
            historyDefaults
        }
    }

    override func tearDown() {
        configDefaults.removePersistentDomain(forName: suiteName)
        historyDefaults.removePersistentDomain(forName: "\(suiteName).history")
        super.tearDown()
    }

    func testMergeUnionsDistinctEntriesByID() {
        let idA = UUID()
        let idB = UUID()
        let local = SyncedSpeechHistory(
            updatedAt: Date(timeIntervalSince1970: 100),
            entries: [
                SpeechHistoryEntry(id: idA, text: "local", createdAt: Date(timeIntervalSince1970: 10))
            ]
        )
        let remote = SyncedSpeechHistory(
            updatedAt: Date(timeIntervalSince1970: 200),
            entries: [
                SpeechHistoryEntry(id: idB, text: "remote", createdAt: Date(timeIntervalSince1970: 20))
            ]
        )

        let merged = SyncedSpeechHistory.merge(local: local, remote: remote)

        XCTAssertEqual(Set(merged.entries.map(\.id)), Set([idA, idB]))
        XCTAssertEqual(merged.updatedAt, remote.updatedAt)
    }

    func testMergeAppliesDeletedEntryIDs() {
        let id = UUID()
        let local = SyncedSpeechHistory(
            entries: [SpeechHistoryEntry(id: id, text: "gone", createdAt: Date())]
        )
        let remote = SyncedSpeechHistory(deletedEntryIDs: [id: Date()])

        let merged = SyncedSpeechHistory.merge(local: local, remote: remote)

        XCTAssertTrue(merged.entries.isEmpty)
        XCTAssertNotNil(merged.deletedEntryIDs[id])
    }

    func testMergeAppliesClearedAt() {
        let clearedAt = Date(timeIntervalSince1970: 500)
        let local = SyncedSpeechHistory(
            entries: [
                SpeechHistoryEntry(text: "old", createdAt: Date(timeIntervalSince1970: 100)),
                SpeechHistoryEntry(text: "new", createdAt: Date(timeIntervalSince1970: 600))
            ]
        )
        let remote = SyncedSpeechHistory(clearedAt: clearedAt)

        let merged = SyncedSpeechHistory.merge(local: local, remote: remote)

        XCTAssertEqual(merged.entries.count, 1)
        XCTAssertEqual(merged.entries.first?.text, "new")
    }

    func testMergeCapsAt300Entries() {
        let localEntries = (0..<200).map { index in
            SpeechHistoryEntry(
                text: "local-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }
        let remoteEntries = (0..<200).map { index in
            SpeechHistoryEntry(
                text: "remote-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index) + 0.5)
            )
        }
        let merged = SyncedSpeechHistory.merge(
            local: SyncedSpeechHistory(entries: localEntries),
            remote: SyncedSpeechHistory(entries: remoteEntries)
        )

        XCTAssertEqual(merged.entries.count, SyncedSpeechHistory.maxEntries)
    }

    func testPullAndMergeAppliesRemoteHistory() async throws {
        let entry = SpeechHistoryEntry(text: "hello", createdAt: Date())
        let remote = SyncedSpeechHistory(updatedAt: Date(), entries: [entry])
        try sync.push(remote)

        await sync.pullAndMerge(store: store)

        let loaded = SpeechHistoryStorage.load(from: historyDefaults)
        XCTAssertEqual(loaded.entries.map(\.text), ["hello"])
    }

    func testMergeAndPushUnionsLocalAndRemote() async throws {
        let localEntry = SpeechHistoryEntry(text: "iphone", createdAt: Date(timeIntervalSince1970: 10))
        SpeechHistoryStorage.save(
            SyncedSpeechHistory(updatedAt: Date(), entries: [localEntry]),
            to: historyDefaults
        )
        let remoteEntry = SpeechHistoryEntry(text: "mac", createdAt: Date(timeIntervalSince1970: 20))
        try sync.push(SyncedSpeechHistory(updatedAt: Date(), entries: [remoteEntry]))

        try await sync.mergeAndPushIfEnabled()

        let loaded = SpeechHistoryStorage.load(from: historyDefaults)
        XCTAssertEqual(Set(loaded.entries.map(\.text)), Set(["iphone", "mac"]))
        XCTAssertEqual(sync.loadRemote()?.entries.count, 2)
    }
}
