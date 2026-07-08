// PersonalDictionaryMergeTests.swift
// OSGKeyboardTests
//
// Hermetic tests for dictionary tombstone merge semantics.

import XCTest
@testable import OSGKeyboardShared

final class PersonalDictionaryMergeTests: XCTestCase {
    func testDeletedEntryDoesNotResurrectFromRemote() {
        let id = UUID()
        let deletedAt = Date()
        let local = PersonalDictionary(
            entries: [],
            deletedEntryIDs: [id: deletedAt]
        )
        let remote = PersonalDictionary(
            entries: [
                PersonalDictionary.Entry(
                    id: id,
                    term: "OSG",
                    category: .productName,
                    source: .manual
                ),
            ]
        )

        let merged = PersonalDictionary.merge(local: local, remote: remote)

        XCTAssertTrue(merged.entries.isEmpty)
        XCTAssertEqual(merged.deletedEntryIDs[id], deletedAt)
    }

    func testClearAllExcludesOlderRemoteEntries() {
        let clearedAt = Date(timeIntervalSince1970: 500)
        let local = PersonalDictionary(entries: [], clearedAt: clearedAt)
        let remote = PersonalDictionary(
            entries: [
                PersonalDictionary.Entry(
                    term: "old",
                    category: .custom,
                    source: .manual,
                    createdAt: Date(timeIntervalSince1970: 100)
                ),
                PersonalDictionary.Entry(
                    term: "new",
                    category: .custom,
                    source: .manual,
                    createdAt: Date(timeIntervalSince1970: 600)
                ),
            ]
        )

        let merged = PersonalDictionary.merge(local: local, remote: remote)

        XCTAssertEqual(merged.entries.count, 1)
        XCTAssertEqual(merged.entries.first?.term, "new")
    }
}
