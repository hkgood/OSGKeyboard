// ClipboardHistoryPolicyTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class ClipboardHistoryPolicyTests: XCTestCase {
    func testRejectsEmptyAndWhitespace() {
        XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: nil))
        XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: "   \n"))
    }

    func testRejectsOTPShapedDigits() {
        XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: "123456"))
        XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: "12-34-56"))
        XCTAssertNotNil(ClipboardHistoryPolicy.acceptedText(from: "订单号 1234567890"))
    }

    func testAcceptsPlainTextAndEmoji() {
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "  hello  "), "hello")
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "你好😀"), "你好😀")
    }

    func testMergeDedupesAndPinsNewest() {
        let a = ClipboardHistoryEntry(text: "a")
        let b = ClipboardHistoryEntry(text: "b")
        let a2 = ClipboardHistoryEntry(text: "a")
        let merged = ClipboardHistoryPolicy.merging(
            incoming: a2,
            into: [a, b],
            limit: 15
        )
        XCTAssertEqual(merged.map(\.text), ["a", "b"])
        XCTAssertEqual(merged.first?.id, a2.id)
    }

    func testWhitespaceTokens() {
        let tokens = ClipboardHistoryPolicy.whitespaceTokens(
            from: "great experience - he writes"
        )
        XCTAssertEqual(tokens, ["great", "experience", "he", "writes"])
    }
}

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
}
