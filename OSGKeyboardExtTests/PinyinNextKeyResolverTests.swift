// PinyinNextKeyResolverTests.swift
// OSGKeyboard · Ext unit tests
//
// Phase 4: legal next-key sets and weighted ambiguous hit resolution.

import XCTest
@testable import OSGKeyboardShared

final class PinyinNextKeyResolverTests: XCTestCase {
    func testZhongPrefixAllowsG() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "zhon",
            schema: .fullPinyin,
            language: .chinese,
            page: .letters
        )
        XCTAssertEqual(keys, ["g"])
    }

    func testCompleteZhongAllowsNewSyllableInitials() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "zhong",
            schema: .fullPinyin,
            language: .chinese,
            page: .letters
        )
        XCTAssertNotNil(keys)
        XCTAssertTrue(keys?.contains("g") == true) // zhongguo
        XCTAssertTrue(keys?.contains("w") == true)
    }

    func testMultiSyllableTrailingGAllowsU() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "zhongg",
            schema: .fullPinyin,
            language: .chinese,
            page: .letters
        )
        XCTAssertTrue(keys?.contains("u") == true) // gu / guo
    }

    func testNiAllowsExtensionAndNewInitial() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "ni",
            schema: .fullPinyin,
            language: .chinese,
            page: .letters
        )
        XCTAssertTrue(keys?.contains("a") == true) // nia…
        XCTAssertTrue(keys?.contains("h") == true) // nihao
    }

    func testEmptyRawDisablesBias() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "",
            schema: .fullPinyin,
            language: .chinese,
            page: .letters
        )
        XCTAssertNil(keys)
    }

    func testEnglishDisablesBias() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "ni",
            schema: .fullPinyin,
            language: .english,
            page: .letters
        )
        XCTAssertNil(keys)
    }

    func testDoublePinyinDisablesBias() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "nihk",
            schema: .microsoftDoublePinyin,
            language: .chinese,
            page: .letters
        )
        XCTAssertNil(keys)
    }

    func testNumbersPageDisablesBias() {
        let keys = PinyinNextKeyResolver.validNextKeys(
            rawInput: "ni",
            schema: .fullPinyin,
            language: .chinese,
            page: .numbers
        )
        XCTAssertNil(keys)
    }

    func testHitWeightsBoostLegalLetters() {
        let keys = [
            TypingKeyHitTarget(
                id: "grid.0.0",
                label: "G",
                visualFrame: .zero,
                behavior: .commitOnRelease
            ),
            TypingKeyHitTarget(
                id: "grid.0.1",
                label: "H",
                visualFrame: .zero,
                behavior: .commitOnRelease
            ),
            TypingKeyHitTarget(
                id: "grid.0.2",
                label: "⌫",
                visualFrame: .zero,
                behavior: .deleteRepeat
            )
        ]
        let weights = PinyinNextKeyResolver.hitWeights(for: keys, validNext: ["g"])
        XCTAssertEqual(weights["grid.0.0"], KeyHitBiasMetrics.legalBoost)
        XCTAssertEqual(weights["grid.0.1"], KeyHitBiasMetrics.illegalShrink)
        XCTAssertNil(weights["grid.0.2"])
    }

    func testWeightedNearestPrefersLegalKeyInGap() {
        let left = TypingKeyHitTarget(
            id: "L",
            label: "F",
            visualFrame: CGRect(x: 0, y: 0, width: 40, height: 50),
            behavior: .commitOnRelease
        )
        let right = TypingKeyHitTarget(
            id: "R",
            label: "G",
            visualFrame: CGRect(x: 46, y: 0, width: 40, height: 50),
            behavior: .commitOnRelease
        )
        let plane = left.visualFrame.union(right.visualFrame)
        // Shared expanded edge (half of 6pt gap) — both frames contain x=43.
        let point = CGPoint(x: 43, y: 25)
        let weighted = KeyHitTesting.hitTarget(
            at: point,
            targets: [left, right],
            keyPlaneBounds: plane,
            horizontalGap: 6,
            verticalGap: 7,
            edgeExpansion: 0,
            hitWeights: [
                "L": KeyHitBiasMetrics.illegalShrink,
                "R": KeyHitBiasMetrics.legalBoost
            ]
        )
        XCTAssertEqual(weighted?.id, "R")
    }

    func testClearSingleHitIgnoresBias() {
        // Point clearly inside F — must not jump to boosted G.
        let left = TypingKeyHitTarget(
            id: "L",
            label: "F",
            visualFrame: CGRect(x: 0, y: 0, width: 40, height: 50),
            behavior: .commitOnRelease
        )
        let right = TypingKeyHitTarget(
            id: "R",
            label: "G",
            visualFrame: CGRect(x: 46, y: 0, width: 40, height: 50),
            behavior: .commitOnRelease
        )
        let plane = left.visualFrame.union(right.visualFrame)
        let point = CGPoint(x: 20, y: 25)
        let hit = KeyHitTesting.hitTarget(
            at: point,
            targets: [left, right],
            keyPlaneBounds: plane,
            horizontalGap: 6,
            verticalGap: 7,
            edgeExpansion: 0,
            hitWeights: [
                "L": KeyHitBiasMetrics.illegalShrink,
                "R": KeyHitBiasMetrics.legalBoost
            ]
        )
        XCTAssertEqual(hit?.id, "L")
    }
}
