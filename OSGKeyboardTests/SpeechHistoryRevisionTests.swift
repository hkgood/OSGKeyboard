import XCTest
@testable import OSGKeyboardShared

@MainActor
final class SpeechHistoryRevisionTests: XCTestCase {
    func testMergePrefersHigherRevisionForSameID() {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 100)
        let old = SpeechHistoryEntry(
            id: id,
            text: "old",
            createdAt: createdAt,
            modifiedAt: createdAt,
            revision: 0
        )
        let edited = SpeechHistoryEntry(
            id: id,
            text: "edited",
            createdAt: createdAt,
            modifiedAt: Date(timeIntervalSince1970: 200),
            revision: 1
        )
        let merged = SyncedSpeechHistory.merge(
            local: SyncedSpeechHistory(entries: [old]),
            remote: SyncedSpeechHistory(entries: [edited])
        )
        XCTAssertEqual(merged.entries, [edited])
    }

    func testMutationUpdatesExistingEntryAndBumpsRevision() throws {
        let suite = "SpeechHistoryRevisionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SpeechHistoryStore(defaults: defaults)
        let entry = try XCTUnwrap(store.append(text: "old"))

        let updated = store.applyHistoryMutation(
            HistoryMutation(
                action: .update,
                entryID: entry.id,
                expectedRevision: entry.revision,
                text: "new"
            )
        )
        XCTAssertEqual(updated?.id, entry.id)
        XCTAssertEqual(updated?.text, "new")
        XCTAssertEqual(updated?.revision, 1)
    }

    func testReplayingMutationDoesNotBumpRevisionOrDuplicate() throws {
        let suite = "SpeechHistoryMutationReplayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SpeechHistoryStore(defaults: defaults)
        let entry = try XCTUnwrap(store.append(text: "old"))
        let mutation = HistoryMutation(
            action: .update,
            entryID: entry.id,
            expectedRevision: 0,
            text: "new"
        )

        let first = store.applyHistoryMutation(mutation)
        let replay = store.applyHistoryMutation(mutation)
        XCTAssertEqual(first, replay)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.revision, 1)
    }
}
