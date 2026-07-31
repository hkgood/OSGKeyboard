// SpeechHistoryDayDeletionTests.swift
// OSGKeyboardTests
//
// Day-boundary and tombstone coverage for History's delete-day action.

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class SpeechHistoryDayDeletionTests: XCTestCase {

    func testDeleteEntriesRemovesOnlySelectedLocalDayAndRecordsTombstones() {
        let suiteName = "group.com.osgkeyboard.shared.tests.delete-day.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let calendar = Calendar.current
        let selectedDay = Date(timeIntervalSince1970: 1_752_163_200)
        let start = calendar.startOfDay(for: selectedDay)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        let previous = SpeechHistoryEntry(
            text: "previous",
            createdAt: start.addingTimeInterval(-1)
        )
        let firstSelected = SpeechHistoryEntry(
            text: "first selected",
            createdAt: start.addingTimeInterval(1)
        )
        let lastSelected = SpeechHistoryEntry(
            text: "last selected",
            createdAt: end.addingTimeInterval(-1)
        )
        let next = SpeechHistoryEntry(
            text: "next",
            createdAt: end
        )
        SpeechHistoryStorage.save(
            SyncedSpeechHistory(
                entries: [next, lastSelected, firstSelected, previous]
            ),
            to: defaults
        )
        let store = SpeechHistoryStore(defaults: defaults)

        store.deleteEntries(on: selectedDay)

        let persisted = SpeechHistoryStorage.load(from: defaults)
        XCTAssertEqual(
            Set(persisted.entries.map(\.id)),
            Set([previous.id, next.id])
        )
        XCTAssertNotNil(persisted.deletedEntryIDs[firstSelected.id])
        XCTAssertNotNil(persisted.deletedEntryIDs[lastSelected.id])
        XCTAssertNil(persisted.deletedEntryIDs[previous.id])
        XCTAssertNil(persisted.deletedEntryIDs[next.id])
    }
}
