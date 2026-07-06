// PersonalDictionaryCloudSyncTests.swift
// OSGKeyboardTests
//
// Hermetic tests for iCloud KVS dictionary merge + sync service.

import XCTest
@testable import OSGKeyboardShared

// MARK: - Fake KVS

private final class FakeUbiquitousKeyValueStore: UbiquitousKeyValueStoreing, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        storage[key]
    }

    func set(_ value: Data?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func synchronize() -> Bool { true }
}

// MARK: - Tests

@MainActor
final class PersonalDictionaryCloudSyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!
    private var kvs: FakeUbiquitousKeyValueStore!
    private var sync: PersonalDictionaryCloudSync!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.sync.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
        kvs = FakeUbiquitousKeyValueStore()
        sync = PersonalDictionaryCloudSync(kvs: kvs) { [unowned self] in store }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Merge

    func testMergeKeepsNewerEntryForSameID() {
        let id = UUID()
        let older = PersonalDictionary.Entry(
            id: id,
            term: "Kubernetes",
            category: .technical,
            source: .manual,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100),
            usageCount: 1
        )
        let newer = PersonalDictionary.Entry(
            id: id,
            term: "Kubernetes",
            aliases: ["k8s"],
            category: .technical,
            source: .manual,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            usageCount: 3
        )

        let merged = PersonalDictionary.merge(
            local: PersonalDictionary(entries: [older]),
            remote: PersonalDictionary(entries: [newer])
        )

        XCTAssertEqual(merged.entries.count, 1)
        XCTAssertEqual(merged.entries[0].aliases, ["k8s"])
        XCTAssertEqual(merged.entries[0].usageCount, 3)
    }

    func testMergeUnionsAliasesForSameCanonicalTerm() {
        let local = PersonalDictionary.Entry(
            term: "Cursor",
            aliases: ["cursor ide"],
            category: .productName,
            source: .manual,
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 150)
        )
        let remote = PersonalDictionary.Entry(
            term: "cursor",
            aliases: ["光标"],
            category: .productName,
            source: .manual,
            createdAt: Date(timeIntervalSince1970: 120),
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let merged = PersonalDictionary.merge(
            local: PersonalDictionary(entries: [local]),
            remote: PersonalDictionary(entries: [remote])
        )

        XCTAssertEqual(merged.entries.count, 1)
        XCTAssertEqual(Set(merged.entries[0].aliases), Set(["cursor ide", "光标"]))
        XCTAssertEqual(merged.entries[0].term, "cursor")
    }

    func testMergeCombinesDistinctTerms() {
        let local = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Alpha", category: .custom, source: .manual),
        ])
        let remote = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Beta", category: .custom, source: .manual),
        ])

        let merged = PersonalDictionary.merge(local: local, remote: remote)
        XCTAssertEqual(Set(merged.entries.map(\.term)), Set(["Alpha", "Beta"]))
    }

    // MARK: - Backward-compatible decode

    func testEntryDecodesWithoutUpdatedAt() throws {
        let json = """
        {
          "id": "A0000000-0000-4000-8000-000000000099",
          "term": "Legacy",
          "aliases": [],
          "category": "custom",
          "source": "manual",
          "createdAt": 1_700_000_000,
          "usageCount": 2
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(PersonalDictionary.Entry.self, from: json)
        XCTAssertEqual(entry.term, "Legacy")
        XCTAssertEqual(entry.updatedAt.timeIntervalSince1970, 1_700_000_000, accuracy: 1)
    }

    // MARK: - Sync service

    func testEnableSyncMergesLocalAndRemoteThenUploads() async throws {
        let remoteEntry = PersonalDictionary.Entry(
            term: "RemoteTerm",
            category: .custom,
            source: .manual,
            updatedAt: Date(timeIntervalSince1970: 500)
        )
        let remoteData = try sync.encode(PersonalDictionary(entries: [remoteEntry]))
        kvs.set(remoteData, forKey: PersonalDictionaryCloudSync.kvsKey)

        store.personalDictionary = PersonalDictionary(entries: [
            PersonalDictionary.Entry(
                term: "LocalTerm",
                category: .custom,
                source: .manual,
                updatedAt: Date(timeIntervalSince1970: 400)
            ),
        ])

        try await sync.enableSync()

        XCTAssertTrue(store.personalDictionaryICloudSyncEnabled)
        XCTAssertEqual(Set(store.personalDictionary.entries.map(\.term)), Set(["LocalTerm", "RemoteTerm"]))
        XCTAssertNotNil(sync.loadRemote())
    }

    func testPushLocalIfEnabledSkipsWhenDisabled() async throws {
        store.personalDictionary = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "OnlyLocal", category: .custom, source: .manual),
        ])
        store.setPersonalDictionaryICloudSyncEnabled(false)

        try await sync.pushLocalIfEnabled(store.personalDictionary)

        XCTAssertNil(sync.loadRemote())
    }

    func testPullAndMergeWritesMergedDictionaryToAppGroup() async {
        store.setPersonalDictionaryICloudSyncEnabled(true)
        store.personalDictionary = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "LocalOnly", category: .custom, source: .manual),
        ])

        let remote = PersonalDictionary(entries: [
            PersonalDictionary.Entry(
                term: "CloudOnly",
                category: .custom,
                source: .manual,
                updatedAt: Date(timeIntervalSince1970: 900)
            ),
        ])
        kvs.set(try! sync.encode(remote), forKey: PersonalDictionaryCloudSync.kvsKey)

        await sync.pullAndMerge(store: store)

        XCTAssertEqual(Set(store.personalDictionary.entries.map(\.term)), Set(["LocalOnly", "CloudOnly"]))
    }

    func testEncodeRejectsOversizedPayload() {
        let hugeTerm = String(repeating: "x", count: PersonalDictionaryCloudSync.maxPayloadBytes)
        let dictionary = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: hugeTerm, category: .custom, source: .manual),
        ])

        XCTAssertThrowsError(try sync.encode(dictionary)) { error in
            guard case .payloadTooLarge = error as? PersonalDictionaryCloudSyncError else {
                return XCTFail("Expected payloadTooLarge, got \(error)")
            }
        }
    }

    func testAppGroupConfigurationDefaultsICloudSyncToOn() {
        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertTrue(config.personalDictionaryICloudSyncEnabled)
    }
}
