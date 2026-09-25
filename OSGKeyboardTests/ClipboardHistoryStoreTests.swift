// ClipboardHistoryStoreTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import Combine
import XCTest

@MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    func testIngestPersistsAndCapsAtFifteen() {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = ClipboardHistoryStore(defaults: suite)
        for index in 0..<20 {
            store.ingest(rawText: "item-\(index)", changeCount: index)
        }
        XCTAssertEqual(store.entries.count, 15)
        XCTAssertEqual(store.entries.first?.text, "item-19")
        XCTAssertEqual(store.entries.last?.text, "item-5")
    }

    func testDisablingCaptureKeepsHistoryUntilExplicitClear() {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = ClipboardHistoryStore(defaults: suite)
        store.ingest(rawText: "keep me", changeCount: 1)

        suite.set(false, forKey: AppGroupConfiguration.Keys.clipboardHistoryEnabled)
        suite.set(false, forKey: AppGroupConfiguration.Keys.clipboardCandidateBarEnabled)
        store.reload()

        XCTAssertEqual(store.entries.map(\.text), ["keep me"])
        store.clearAll()
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertTrue(ClipboardHistoryStore(defaults: suite).entries.isEmpty)
    }

    func testLoadRemovesOversizedLegacyRowsAndDeduplicates() throws {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let first = ClipboardHistoryEntry(text: "duplicate")
        let duplicate = ClipboardHistoryEntry(text: "duplicate")
        let oversized = ClipboardHistoryEntry(
            text: String(repeating: "x", count: ClipboardHistoryPolicy.maxEntryUTF8Bytes + 1)
        )
        suite.set(
            try JSONEncoder().encode([first, oversized, duplicate]),
            forKey: ClipboardHistoryStore.Keys.entries
        )

        let store = ClipboardHistoryStore(defaults: suite)

        XCTAssertEqual(store.entries, [first])
        let persisted = try XCTUnwrap(suite.data(forKey: ClipboardHistoryStore.Keys.entries))
        XCTAssertEqual(
            try JSONDecoder().decode([ClipboardHistoryEntry].self, from: persisted),
            [first]
        )
    }

    func testRejectedIngestStillCleansOversizedLegacyRows() throws {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let oversized = ClipboardHistoryEntry(
            text: String(repeating: "x", count: ClipboardHistoryPolicy.maxEntryUTF8Bytes + 1)
        )
        suite.set(
            try JSONEncoder().encode([oversized]),
            forKey: ClipboardHistoryStore.Keys.entries
        )
        let store = ClipboardHistoryStore(defaults: suite)

        XCTAssertNil(store.ingest(rawText: "123456", changeCount: 2))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testPayloadLimitDropsOldestRowsAndKeepsNewestText() {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = ClipboardHistoryStore(defaults: suite)

        for index in 0..<15 {
            let text = "\(index)-" + String(repeating: "\"", count: 12_000)
            XCTAssertNotNil(store.ingest(rawText: text, changeCount: index))
        }

        XCTAssertTrue(store.entries.first?.text.hasPrefix("14-") == true)
        XCTAssertTrue(ClipboardHistoryPolicy.encodedPayloadFitsLimit(store.entries))
        XCTAssertLessThan(store.entries.count, ClipboardHistoryPolicy.maxEntries)
    }

    func testRecentlyAutoRepliedOnlyWithinWindowAndForSameText() {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let store = ClipboardHistoryStore(defaults: suite)
        let firedAt = Date()

        XCTAssertFalse(store.recentlyAutoReplied(text: "hello", now: firedAt))

        store.markAutoReplied(text: "hello", changeCount: 7, at: firedAt)

        // Universal Clipboard re-sync: same text seconds later stays suppressed.
        XCTAssertTrue(
            store.recentlyAutoReplied(text: "hello", now: firedAt.addingTimeInterval(5))
        )
        // A different copy inside the window still fires.
        XCTAssertFalse(
            store.recentlyAutoReplied(text: "different", now: firedAt.addingTimeInterval(5))
        )
        // A deliberate re-copy after the window fires again.
        XCTAssertFalse(
            store.recentlyAutoReplied(text: "hello", now: firedAt.addingTimeInterval(31))
        )
        XCTAssertEqual(store.lastAutoRepliedChangeCount, 7)
    }

    func testAutoReplyMarkersPersistAcrossStoreInstances() {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let firedAt = Date()
        ClipboardHistoryStore(defaults: suite)
            .markAutoReplied(text: "persisted", changeCount: 9, at: firedAt)

        let reloaded = ClipboardHistoryStore(defaults: suite)

        XCTAssertEqual(reloaded.lastAutoRepliedChangeCount, 9)
        XCTAssertEqual(reloaded.lastAutoRepliedAt, firedAt)
        XCTAssertTrue(
            reloaded.recentlyAutoReplied(text: "persisted", now: firedAt.addingTimeInterval(1))
        )
    }

    /// The lost-update this fixes: the host keeps a long-lived
    /// `ClipboardHistoryStore` whose `entries` only refreshed on view appear.
    /// History is one whole-array blob, so a host-side delete made against a
    /// stale array wrote back entries the keyboard had just captured or removed.
    func testPeerWriteReachesStaleStoreBeforeItOverwritesHistory() async throws {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let host = ClipboardHistoryStore(defaults: suite)
        host.startObservingCrossProcessChanges()
        host.ingest(rawText: "host-a", changeCount: 1)
        host.ingest(rawText: "host-b", changeCount: 2)

        // The keyboard extension captures a new copy while the host sits on a
        // settings screen that loaded its list earlier.
        let keyboard = ClipboardHistoryStore(defaults: suite)
        keyboard.startObservingCrossProcessChanges()

        let synced = expectation(description: "host store reloads after the peer write")
        var cancellable: AnyCancellable?
        cancellable = host.$entries.sink { entries in
            if entries.contains(where: { $0.text == "keyboard-c" }) { synced.fulfill() }
        }
        keyboard.ingest(rawText: "keyboard-c", changeCount: 3)
        await fulfillment(of: [synced], timeout: 2)
        cancellable?.cancel()

        // The host now deletes an old row. Before the fix this persisted its
        // stale [host-b, host-a] and silently dropped keyboard-c.
        let hostA = try XCTUnwrap(host.entries.first { $0.text == "host-a" })
        host.remove(id: hostA.id)

        XCTAssertEqual(
            ClipboardHistoryStore(defaults: suite).entries.map(\.text),
            ["keyboard-c", "host-b"]
        )
    }

    func testPersistBumpsRevisionAndReloadAdoptsIt() {
        let suiteName = "ClipboardHistoryStoreTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let writer = ClipboardHistoryStore(defaults: suite)
        XCTAssertEqual(suite.integer(forKey: ClipboardHistoryStore.Keys.revision), 0)
        writer.ingest(rawText: "one", changeCount: 1)
        let afterFirst = suite.integer(forKey: ClipboardHistoryStore.Keys.revision)
        XCTAssertGreaterThan(afterFirst, 0)
        writer.ingest(rawText: "two", changeCount: 2)
        XCTAssertGreaterThan(
            suite.integer(forKey: ClipboardHistoryStore.Keys.revision),
            afterFirst
        )
    }
}
