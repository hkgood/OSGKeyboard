// ClipboardHistoryStoreTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
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
}
