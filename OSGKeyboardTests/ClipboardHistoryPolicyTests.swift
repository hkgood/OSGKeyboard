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
        XCTAssertNotNil(ClipboardHistoryPolicy.acceptedText(from: "订单号 123456"))
        XCTAssertNotNil(ClipboardHistoryPolicy.acceptedText(from: "账号 123456"))
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "2026"), "2026")
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "08-11"), "08-11")
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "2026-08-11"), "2026-08-11")
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "20260811"), "20260811")
        XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: "02-31"))
        XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: "20260231"))
    }

    func testAcceptsPlainTextAndEmoji() {
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "  hello  "), "hello")
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "你好😀"), "你好😀")
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: "acct-123"), "acct-123")
    }

    func testSecureFieldPasteboardGenerationRemainsSuppressedAfterFocusChanges() {
        XCTAssertTrue(
            ClipboardHistoryPolicy.shouldSuppressCapture(
                changeCount: 42,
                secureFieldSuppressedChangeCount: 42
            )
        )
        XCTAssertFalse(
            ClipboardHistoryPolicy.shouldSuppressCapture(
                changeCount: 43,
                secureFieldSuppressedChangeCount: 42
            )
        )
    }

    func testRejectsConservativeSensitiveContentMatrix() {
        let jwt = """
        eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.\
        eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkphbmUgRG9lIn0.\
        SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
        """
        let rejected: [(String, ClipboardHistoryPolicy.RejectionReason)] = [
            ("-----BEGIN PRIVATE KEY-----", .privateKey),
            ("-----BEGIN RSA PRIVATE KEY-----", .privateKey),
            (jwt, .jwt),
            ("Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345", .bearerToken),
            ("Bearer abcd+efgh/ijklmnop==", .bearerToken),
            ("sk-proj-abcdefghijklmnopqrstuvwxyz0123456789", .providerKey),
            ("sk-ant-abcdefghijklmnopqrstuvwxyz0123456789", .providerKey),
            ("github_pat_abcdefghijklmnopqrstuvwxyz012345", .providerKey),
            ("4111 1111 1111 1111", .paymentCard),
        ]

        for (text, reason) in rejected {
            XCTAssertEqual(
                ClipboardHistoryPolicy.rejectionReason(for: text),
                reason,
                "Expected \(reason) for \(text)"
            )
            XCTAssertNil(ClipboardHistoryPolicy.acceptedText(from: text))
        }
    }

    func testSensitiveFilterAvoidsCommonFalsePositives() {
        let accepted = [
            "Bearer is an authentication scheme",
            "sk-short-example",
            "订单号 1234567890",
            "年份 2026",
            "账号 123456",
            "4111 1111 1111 1112",
            "490154203237518",
        ]
        for text in accepted {
            XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: text), text)
        }
    }

    func testEntryAndPayloadByteBoundaries() {
        let exactEntry = String(repeating: "x", count: ClipboardHistoryPolicy.maxEntryUTF8Bytes)
        let oversizedEntry = exactEntry + "x"
        XCTAssertEqual(ClipboardHistoryPolicy.acceptedText(from: exactEntry), exactEntry)
        XCTAssertEqual(
            ClipboardHistoryPolicy.rejectionReason(for: oversizedEntry),
            .exceedsEntrySize
        )

        let fifteen = (0..<15).map { index in
            ClipboardHistoryEntry(text: String(repeating: Character("\(index % 10)"), count: 16_000))
        }
        let seventeen = (0..<17).map { index in
            ClipboardHistoryEntry(text: "\(index)-" + String(repeating: "x", count: 16_000))
        }
        XCTAssertTrue(ClipboardHistoryPolicy.encodedPayloadFitsLimit(fifteen))
        XCTAssertFalse(ClipboardHistoryPolicy.encodedPayloadFitsLimit(seventeen))
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
