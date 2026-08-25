// PersonalDictionaryEntryServiceTests.swift
// OSGKeyboardTests
//
// Verifies that every manual-entry UI gets the same alias-generation behavior
// without allowing a late asynchronous response to overwrite newer edits.

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class PersonalDictionaryEntryServiceTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.entry-service.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testSuggestedTermGeneratesAliasesAndPreservesUsageCount() async throws {
        var pushedDictionaries: [PersonalDictionary] = []
        let service = PersonalDictionaryEntryService(
            store: store,
            aliasGeneration: { _ in ["洛基", "肉鸡"] },
            cloudPush: { pushedDictionaries.append($0) }
        )

        let saved = try XCTUnwrap(
            service.saveEntry(term: "Rocky", source: .history, minimumUsageCount: 3)
        )
        XCTAssertTrue(saved.shouldGenerateAliases)
        XCTAssertEqual(saved.dictionary.entries.first?.source, .history)
        XCTAssertEqual(saved.dictionary.entries.first?.usageCount, 3)
        XCTAssertTrue(saved.dictionary.entries.first?.aliases.isEmpty == true)

        let finished = await service.finishSaving(saved)

        XCTAssertEqual(Set(finished.entries.first?.aliases ?? []), Set(["洛基", "肉鸡"]))
        XCTAssertEqual(finished.entries.first?.usageCount, 3)
        XCTAssertEqual(pushedDictionaries.count, 2)
    }

    func testAliasCompletionPreservesChangesMadeWhileGenerating() async throws {
        let service = PersonalDictionaryEntryService(
            store: store,
            aliasGeneration: { _ in ["swift u i"] },
            cloudPush: { _ in }
        )
        let saved = try XCTUnwrap(service.saveEntry(term: "SwiftUI", source: .manual))
        store.updatePersonalDictionary { dictionary -> UUID? in
            guard let concurrent = dictionary.upsertManual(term: "Cursor") else { return nil }
            dictionary.version += 1
            return concurrent.id
        }

        let finished = await service.finishSaving(saved)

        XCTAssertEqual(Set(finished.entries.map(\.term)), Set(["SwiftUI", "Cursor"]))
        XCTAssertEqual(
            finished.entry(matchingTerm: "SwiftUI")?.aliases,
            ["swift u i"]
        )
    }

    func testAliasCompletionDoesNotRestoreDeletedEntry() async throws {
        let service = PersonalDictionaryEntryService(
            store: store,
            aliasGeneration: { _ in ["late alias"] },
            cloudPush: { _ in }
        )
        let saved = try XCTUnwrap(service.saveEntry(term: "Deleted", source: .manual))
        store.deletePersonalDictionaryEntry(id: saved.entryID)

        let finished = await service.finishSaving(saved)

        XCTAssertNil(finished.entries.first(where: { $0.id == saved.entryID }))
        XCTAssertNotNil(finished.deletedEntryIDs[saved.entryID])
    }

    func testAliasCompletionIgnoresEntryRenamedAfterSave() async throws {
        let service = PersonalDictionaryEntryService(
            store: store,
            aliasGeneration: { _ in ["stale alias"] },
            cloudPush: { _ in }
        )
        let saved = try XCTUnwrap(service.saveEntry(term: "Before", source: .manual))
        store.updatePersonalDictionary { dictionary -> UUID? in
            guard let renamed = dictionary.upsertManual(
                term: "After",
                existingID: saved.entryID
            ) else {
                return nil
            }
            dictionary.version += 1
            return renamed.id
        }

        let finished = await service.finishSaving(saved)

        XCTAssertEqual(finished.entries.first?.term, "After")
        XCTAssertTrue(finished.entries.first?.aliases.isEmpty == true)
    }

    func testAliasGenerationFailureKeepsSavedEntry() async throws {
        var pushCount = 0
        let service = PersonalDictionaryEntryService(
            store: store,
            aliasGeneration: { _ in [] },
            cloudPush: { _ in pushCount += 1 }
        )
        let saved = try XCTUnwrap(service.saveEntry(term: "Durable", source: .manual))

        let finished = await service.finishSaving(saved)

        XCTAssertEqual(finished.entries.first?.term, "Durable")
        XCTAssertTrue(finished.entries.first?.aliases.isEmpty == true)
        XCTAssertEqual(pushCount, 1)
    }
}
