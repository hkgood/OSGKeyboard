// RimeFrequentTermStoreTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class RimeFrequentTermStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "RimeFrequentTermStoreTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testRepeatedRimeCommitBecomesSuggestion() {
        let store = RimeFrequentTermStore(defaults: defaults)
        store.recordCommittedText("少数派")
        XCTAssertTrue(store.suggestions(excludingPersonalTerms: []).isEmpty)

        store.recordCommittedText("少数派")

        let suggestion = store.suggestions(excludingPersonalTerms: []).first
        XCTAssertEqual(suggestion?.term, "少数派")
        XCTAssertEqual(suggestion?.commitCount, 2)
    }

    func testSuggestionsExcludeExistingDictionaryTermsAndCommonWords() {
        let store = RimeFrequentTermStore(defaults: defaults)
        for _ in 0..<4 {
            store.recordCommittedText("我们")
            store.recordCommittedText("飞书文档")
            store.recordCommittedText("微信读书")
        }

        let suggestions = store.suggestions(
            excludingPersonalTerms: ["飞书文档"]
        )

        XCTAssertEqual(suggestions.map(\.term), ["微信读书"])
    }

    func testSuggestionsRankFrequencyBeforeRecency() {
        let store = RimeFrequentTermStore(defaults: defaults)
        let earlier = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        for _ in 0..<3 {
            store.recordCommittedText("光锥之内", at: earlier)
        }
        for _ in 0..<2 {
            store.recordCommittedText("即刻笔记", at: later)
        }

        XCTAssertEqual(
            store.suggestions(excludingPersonalTerms: []).map(\.term),
            ["光锥之内", "即刻笔记"]
        )
    }

    func testPunctuationAndSingleCharactersAreIgnored() {
        let store = RimeFrequentTermStore(defaults: defaults)
        for _ in 0..<3 {
            store.recordCommittedText("我")
            store.recordCommittedText("你好！")
            store.recordCommittedText("\n")
        }

        XCTAssertTrue(store.suggestions(excludingPersonalTerms: []).isEmpty)
    }

    func testClearRemovesLearnedSuggestions() {
        let store = RimeFrequentTermStore(defaults: defaults)
        store.recordCommittedText("少数派")
        store.recordCommittedText("少数派")
        XCTAssertFalse(store.suggestions(excludingPersonalTerms: []).isEmpty)

        store.clear()

        XCTAssertTrue(store.suggestions(excludingPersonalTerms: []).isEmpty)
    }
}
