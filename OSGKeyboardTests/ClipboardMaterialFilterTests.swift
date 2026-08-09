// ClipboardMaterialFilterTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class ClipboardMaterialFilterTests: XCTestCase {

    func testRejectsEmpty() {
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("   "), .rejected(.empty))
    }

    func testRejectsPhoneAndNumeric() {
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("13812345678"), .rejected(.phoneOrNumeric))
        XCTAssertEqual(
            ClipboardMaterialFilter.evaluate("+86 138-1234-5678"),
            .rejected(.phoneOrNumeric)
        )
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("123-456"), .rejected(.phoneOrNumeric))
    }

    func testRejectsEmojiOrSymbolOnly() {
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("😀😀😀"), .rejected(.emojiOrSymbolOnly))
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("！！！"), .rejected(.emojiOrSymbolOnly))
    }

    func testRejectsVerificationCode() {
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("A8f2K1"), .rejected(.verificationCode))
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("x9Y2"), .rejected(.verificationCode))
    }

    func testRejectsTooShort() {
        // 周末吃饭吗 = 5 graphemes
        XCTAssertEqual(ClipboardMaterialFilter.evaluate("周末吃饭吗"), .rejected(.tooShort))
        let fourteen = String(repeating: "啊", count: 14)
        XCTAssertEqual(ClipboardMaterialFilter.evaluate(fourteen), .rejected(.tooShort))
    }

    func testRejectsRepetitiveSpam() {
        let spam = String(repeating: "啊", count: 15)
        XCTAssertEqual(ClipboardMaterialFilter.evaluate(spam), .rejected(.repetitiveSpam))
    }

    func testAcceptsNaturalLanguage() {
        let text = "周末有空一起吃个饭吗？我想聊下项目进度。"
        switch ClipboardMaterialFilter.evaluate(text) {
        case .eligible(let snapshot):
            XCTAssertEqual(snapshot, text)
        case .rejected(let reason):
            XCTFail("expected eligible, got \(reason)")
        }
    }

    func testAllowsDigitsInsideNaturalSentence() {
        let text = "明天 3 点见，我们在咖啡厅门口碰头再走。"
        if case .rejected = ClipboardMaterialFilter.evaluate(text) {
            XCTFail("sentence with digits should remain eligible")
        }
    }

    func testTruncateSnapshot() {
        let long = String(repeating: "汉", count: 3_050)
        let truncated = ClipboardMaterialFilter.truncateSnapshot(long)
        XCTAssertEqual(truncated.count, ClipboardMaterialFilter.maxSnapshotLength)
    }

    func testConstantsMatchPlan() {
        XCTAssertEqual(ClipboardMaterialFilter.minimumLength, 15)
        XCTAssertEqual(ClipboardMaterialFilter.maxSnapshotLength, 3_000)
        XCTAssertEqual(ClipboardMaterialFilter.longPressDuration, 0.45, accuracy: 0.001)
        XCTAssertEqual(ClipboardMaterialFilter.minimumRecordingAfterHostConfirm, 0.70, accuracy: 0.001)
        XCTAssertEqual(ClipboardMaterialFilter.failureHintDuration, 2.5, accuracy: 0.001)
    }
}
