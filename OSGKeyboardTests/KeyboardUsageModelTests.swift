// KeyboardUsageModelTests.swift
// OSGKeyboardTests
//
// Unicode classification, fixed insertion sources and wire privacy boundaries.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class KeyboardUsageModelTests: XCTestCase {
    func testHanClassificationCoversSimplifiedTraditionalAndExtensionIdeographs() {
        let counts = KeyboardUsageCharacterClassifier.classify("汉漢𠀀")

        XCTAssertEqual(counts.chinese, 3)
        XCTAssertEqual(counts.english, 0)
        XCTAssertEqual(counts.other, 0)
        XCTAssertEqual(counts.total, 3)
    }

    func testLatinLettersAndOtherCharactersUseExtendedGraphemeCounts() {
        let counts = KeyboardUsageCharacterClassifier.classify(
            "AzéÅ 12,.🙂👨‍👩‍👧‍👦\n"
        )

        XCTAssertEqual(counts.chinese, 0)
        XCTAssertEqual(counts.english, 4)
        // Space, two digits, comma, period, two Emoji graphemes and newline.
        XCTAssertEqual(counts.other, 8)
        XCTAssertEqual(counts.total, 12)
    }

    func testHanTakesPrecedenceWhenOneGraphemeContainsMultipleScripts() {
        let counts = KeyboardUsageCharacterClassifier.classify("汉\u{FE0F}")

        XCTAssertEqual(counts, KeyboardUsageCharacterCounts(chinese: 1))
    }

    func testOnlyManualKeyboardSourceContributes() {
        XCTAssertTrue(
            KeyboardTextInsertionSource.manualKeyboard.contributesToKeyboardUsage
        )
        for source in KeyboardTextInsertionSource.allCases
            where source != .manualKeyboard {
            XCTAssertFalse(
                source.contributesToKeyboardUsage,
                "\(source.rawValue) must remain excluded"
            )
        }
    }

    func testSummaryEncodingHasOnlyNumericDateVersionAndUUIDFields() throws {
        let summary = try makeSummary()
        let request = KeyboardUsageUploadRequest(
            installationId: analyticsTestUUID(1),
            summaries: [summary]
        )
        let data = try JSONEncoder().encode(request)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(Set(root.keys), ["installationId", "summaries"])
        let encodedSummary = try XCTUnwrap(
            (root["summaries"] as? [[String: Any]])?.first
        )
        XCTAssertEqual(
            Set(encodedSummary.keys),
            [
                "clientSummaryId",
                "summaryDate",
                "chineseCharacterCount",
                "englishCharacterCount",
                "otherCharacterCount",
                "inputSessionCount",
                "chineseOnlySessionCount",
                "englishOnlySessionCount",
                "mixedLanguageSessionCount",
                "otherOnlySessionCount",
                "appVersion",
                "osVersion"
            ]
        )
        for forbidden in [
            "text",
            "pinyin",
            "candidate",
            "context",
            "hostApp",
            "bundleId",
            "transcript",
            "prompt",
            "clipboard",
            "properties"
        ] {
            XCTAssertFalse(encodedSummary.keys.contains(forbidden))
        }
    }

    func testSummaryRejectsUnknownFieldsAndInvalidSessionPartition() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(try makeSummary())
            ) as? [String: Any]
        )
        object["rawText"] = "never allowed"
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                KeyboardUsageSummary.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
        ) { error in
            guard case KeyboardUsageModelError.unknownField("rawText") = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertThrowsError(
            try KeyboardUsageSummary(
                clientSummaryId: analyticsTestUUID(3),
                summaryDate: "2026-08-20",
                chineseCharacterCount: 1,
                englishCharacterCount: 0,
                otherCharacterCount: 0,
                inputSessionCount: 2,
                chineseOnlySessionCount: 1,
                englishOnlySessionCount: 0,
                mixedLanguageSessionCount: 0,
                otherOnlySessionCount: 0,
                appVersion: "2.0.0",
                osVersion: "26.0"
            )
        )
    }

    func testCounterAndVersionBoundariesAreEnforced() throws {
        XCTAssertEqual(
            KeyboardUsageCharacterCounts(chinese: Int.max).chinese,
            1_000_000
        )
        XCTAssertEqual(
            KeyboardUsageCharacterCounts(english: -1).english,
            0
        )
        XCTAssertNoThrow(
            try KeyboardUsageSummary(
                clientSummaryId: analyticsTestUUID(4),
                summaryDate: "2026-08-20",
                chineseCharacterCount: 1_000_000,
                englishCharacterCount: 1_000_000,
                otherCharacterCount: 1_000_000,
                inputSessionCount: 100_000,
                chineseOnlySessionCount: 25_000,
                englishOnlySessionCount: 25_000,
                mixedLanguageSessionCount: 25_000,
                otherOnlySessionCount: 25_000,
                appVersion: String(repeating: "a", count: 32),
                osVersion: "26.0"
            )
        )
        XCTAssertThrowsError(
            try KeyboardUsageSummary(
                clientSummaryId: analyticsTestUUID(5),
                summaryDate: "2026-08-20",
                chineseCharacterCount: 1_000_001,
                englishCharacterCount: 0,
                otherCharacterCount: 0,
                inputSessionCount: 1,
                chineseOnlySessionCount: 1,
                englishOnlySessionCount: 0,
                mixedLanguageSessionCount: 0,
                otherOnlySessionCount: 0,
                appVersion: "2.0.0",
                osVersion: "26.0"
            )
        )
    }

    private func makeSummary() throws -> KeyboardUsageSummary {
        try KeyboardUsageSummary(
            clientSummaryId: analyticsTestUUID(2),
            summaryDate: "2026-08-20",
            chineseCharacterCount: 2,
            englishCharacterCount: 1,
            otherCharacterCount: 1,
            inputSessionCount: 2,
            chineseOnlySessionCount: 1,
            englishOnlySessionCount: 0,
            mixedLanguageSessionCount: 1,
            otherOnlySessionCount: 0,
            appVersion: "2.0.0",
            osVersion: "26.0"
        )
    }
}
