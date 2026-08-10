// KeyHitTestingTests.swift
// OSGKeyboard · Ext unit tests
//
// Phase 1 / 3: gap fill, nearest-center, intent offset, edge expansion.

import XCTest
@testable import OSGKeyboardShared

final class KeyHitTestingTests: XCTestCase {
    private func makePairTargets(
        left: CGRect = CGRect(x: 0, y: 0, width: 40, height: 50),
        gap: CGFloat = 6
    ) -> (targets: [TypingKeyHitTarget], plane: CGRect) {
        let right = CGRect(
            x: left.maxX + gap,
            y: left.minY,
            width: left.width,
            height: left.height
        )
        let targets = [
            TypingKeyHitTarget(
                id: "L",
                label: "A",
                visualFrame: left,
                behavior: .commitOnRelease
            ),
            TypingKeyHitTarget(
                id: "R",
                label: "S",
                visualFrame: right,
                behavior: .commitOnRelease
            )
        ]
        let plane = left.union(right)
        return (targets, plane)
    }

    func testGapMidpointHitsNearestKey() {
        let pair = makePairTargets()
        let mid = CGPoint(x: 43, y: 25) // center of 6pt gap between 40 and 46
        let hit = KeyHitTesting.hitTarget(
            at: mid,
            targets: pair.targets,
            keyPlaneBounds: pair.plane,
            horizontalGap: 6,
            verticalGap: 7,
            edgeExpansion: 0
        )
        // Midpoint is equidistant; either is acceptable, but must not miss.
        XCTAssertNotNil(hit)
    }

    func testGapCloserToLeftSelectsLeft() {
        let pair = makePairTargets()
        // Just right of left key visual edge, still in gap, closer to left center.
        let point = CGPoint(x: 41, y: 25)
        let hit = KeyHitTesting.hitTarget(
            at: point,
            targets: pair.targets,
            keyPlaneBounds: pair.plane,
            horizontalGap: 6,
            verticalGap: 7,
            edgeExpansion: 0
        )
        XCTAssertEqual(hit?.id, "L")
    }

    func testGapCloserToRightSelectsRight() {
        let pair = makePairTargets()
        let point = CGPoint(x: 45, y: 25)
        let hit = KeyHitTesting.hitTarget(
            at: point,
            targets: pair.targets,
            keyPlaneBounds: pair.plane,
            horizontalGap: 6,
            verticalGap: 7,
            edgeExpansion: 0
        )
        XCTAssertEqual(hit?.id, "R")
    }

    func testOutsidePlaneReturnsNil() {
        let pair = makePairTargets()
        let hit = KeyHitTesting.hitTarget(
            at: CGPoint(x: 200, y: 200),
            targets: pair.targets,
            keyPlaneBounds: pair.plane,
            horizontalGap: 6,
            verticalGap: 7,
            edgeExpansion: 0
        )
        XCTAssertNil(hit)
    }

    func testIntentOffsetShiftsHitUpward() {
        // Key occupies y 10…60. Raw touch at y=62 is below the key; with a
        // 4pt upward intent offset it maps to y=58 and should still hit.
        let target = TypingKeyHitTarget(
            id: "K",
            label: "M",
            visualFrame: CGRect(x: 0, y: 10, width: 40, height: 50),
            behavior: .commitOnRelease
        )
        let plane = target.visualFrame
        let raw = CGPoint(x: 20, y: 62)
        let withoutOffset = KeyHitTesting.hitTarget(
            at: raw,
            targets: [target],
            keyPlaneBounds: plane,
            horizontalGap: 0,
            verticalGap: 0,
            edgeExpansion: 0
        )
        let withOffset = KeyHitTesting.hitTarget(
            rawTouch: raw,
            targets: [target],
            keyPlaneBounds: plane,
            horizontalGap: 0,
            verticalGap: 0,
            intentOffsetY: 4,
            edgeExpansion: 0
        )
        XCTAssertNil(withoutOffset)
        XCTAssertEqual(withOffset?.id, "K")
    }

    func testEdgeExpansionExtendsOuterHit() {
        let target = TypingKeyHitTarget(
            id: "Q",
            label: "Q",
            visualFrame: CGRect(x: 10, y: 0, width: 40, height: 50),
            behavior: .commitOnRelease
        )
        let plane = target.visualFrame
        // Point just left of the visual key, inside edge expansion.
        let point = CGPoint(x: 7, y: 25)
        let hit = KeyHitTesting.hitTarget(
            at: point,
            targets: [target],
            keyPlaneBounds: plane,
            horizontalGap: 0,
            verticalGap: 0,
            edgeExpansion: 5
        )
        XCTAssertEqual(hit?.id, "Q")
    }

    func testLayoutBuilderCoversGapsBetweenKeys() {
        let layout = TypingKeyLayoutBuilder.build(
            size: CGSize(width: 300, height: 200),
            letterRows: [
                ["Q", "W", "E"],
                ["A", "S", "D"],
                ["Z", "X", "C"]
            ],
            pageSwitchLabel: "123",
            spaceLabel: "space",
            returnLabel: "return",
            keyWeight: { _, _, _ in 1 }
        )
        // 9 letters + 4 bottom (globe · pageSwitch · space · return)
        XCTAssertEqual(layout.keys.count, 13)

        // Mid-gap between Q and W on first row should hit something.
        let q = layout.keys.first { $0.label == "Q" }!
        let w = layout.keys.first { $0.label == "W" }!
        let mid = CGPoint(x: (q.visualFrame.maxX + w.visualFrame.minX) / 2, y: q.center.y)
        let hit = KeyHitTesting.hitTarget(
            at: mid,
            targets: layout.keys,
            keyPlaneBounds: layout.keyPlaneBounds,
            horizontalGap: layout.horizontalGap,
            verticalGap: layout.verticalGap
        )
        XCTAssertNotNil(hit)
        XCTAssertTrue(hit?.label == "Q" || hit?.label == "W")
    }

    func testBehaviorResolver() {
        XCTAssertEqual(TypingKeyBehaviorResolver.behavior(for: "⌫"), .deleteRepeat)
        XCTAssertEqual(TypingKeyBehaviorResolver.behavior(for: "⇧"), .shiftHold)
        XCTAssertEqual(TypingKeyBehaviorResolver.behavior(for: "A"), .commitOnRelease)
        XCTAssertEqual(TypingKeyBehaviorResolver.behavior(for: "123"), .commitOnRelease)
    }
}
