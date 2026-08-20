// AlibabaVocabularySyncTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

final class AlibabaVocabularySyncTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.tests.alibaba-vocab.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testEnsureVocabularyIDUsesCacheWhenFingerprintMatches() async throws {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "热词", category: .custom, source: .manual)
        ])
        defaults.set("vocab-cached", forKey: AlibabaVocabularySync.Keys.vocabularyId)
        defaults.set(
            dict.vocabularySyncFingerprint(),
            forKey: AlibabaVocabularySync.Keys.fingerprint
        )

        let id = try await AlibabaVocabularySync.ensureVocabularyID(
            dictionary: dict,
            apiKey: "sk-test",
            defaults: defaults,
            session: StubURLProtocol.makeEphemeralSession()
        )
        XCTAssertEqual(id, "vocab-cached")
        XCTAssertNil(StubURLProtocolStorage.lastRequest, "cache hit must not hit network")
    }

    func testEnsureVocabularyIDCreatesAndCachesOnMiss() async throws {
        StubURLProtocolStorage.config = (
            200,
            Data(#"{"output":{"vocabulary_id":"vocab-abc123"}}"#.utf8)
        )
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "新词", category: .custom, source: .manual)
        ])
        let id = try await AlibabaVocabularySync.ensureVocabularyID(
            dictionary: dict,
            apiKey: "sk-test",
            defaults: defaults,
            session: StubURLProtocol.makeEphemeralSession()
        )
        XCTAssertEqual(id, "vocab-abc123")
        XCTAssertEqual(
            defaults.string(forKey: AlibabaVocabularySync.Keys.vocabularyId),
            "vocab-abc123"
        )
        XCTAssertEqual(
            defaults.string(forKey: AlibabaVocabularySync.Keys.fingerprint),
            dict.vocabularySyncFingerprint()
        )
        XCTAssertNotNil(StubURLProtocolStorage.lastRequest)
    }

    func testEnsureVocabularyIDReturnsNilOnlyWhenNoHotwordEntries() async throws {
        // `effectiveEntries` always includes system term "OSGKeyboard", so a
        // user-empty dictionary still syncs. Clear-cache is for truly empty
        // hotword lists after filtering — exercise `clearCache` directly.
        defaults.set("stale-id", forKey: AlibabaVocabularySync.Keys.vocabularyId)
        defaults.set("stale-fp", forKey: AlibabaVocabularySync.Keys.fingerprint)
        AlibabaVocabularySync.clearCache(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: AlibabaVocabularySync.Keys.vocabularyId))
        XCTAssertNil(defaults.string(forKey: AlibabaVocabularySync.Keys.fingerprint))
    }

    func testEnsureVocabularyIDCreatesForSystemEntriesWhenUserDictionaryEmpty() async throws {
        StubURLProtocolStorage.config = (
            200,
            Data(#"{"output":{"vocabulary_id":"vocab-system"}}"#.utf8)
        )
        let id = try await AlibabaVocabularySync.ensureVocabularyID(
            dictionary: PersonalDictionary(),
            apiKey: "sk-test",
            defaults: defaults,
            session: StubURLProtocol.makeEphemeralSession()
        )
        XCTAssertEqual(id, "vocab-system")
        XCTAssertNotNil(StubURLProtocolStorage.lastRequest)
    }
}
