// TypingTouchTrackerTests.swift
// OSGKeyboard · Ext unit tests
//
// Multi-finger overlap: press order commits, Shift hold + type, slide reselect.

@testable import OSGKeyboardShared
import XCTest

final class TypingTouchTrackerTests: XCTestCase {
    private final class Token {}

    private func letter(_ id: String) -> TypingKeyHitTarget {
        TypingKeyHitTarget(
            id: id,
            label: id,
            visualFrame: .zero,
            behavior: .commitOnRelease
        )
    }

    private func shiftKey() -> TypingKeyHitTarget {
        TypingKeyHitTarget(
            id: "shift",
            label: "⇧",
            visualFrame: .zero,
            behavior: .shiftHold
        )
    }

    private func deleteKey() -> TypingKeyHitTarget {
        TypingKeyHitTarget(
            id: "delete",
            label: "⌫",
            visualFrame: .zero,
            behavior: .deleteRepeat
        )
    }

    func testSecondFingerDownCommitsFirstInPressOrder() {
        let tracker = TypingTouchTracker()
        let a = Token()
        let b = Token()
        let keyA = letter("a")
        let keyB = letter("b")

        let downA = tracker.began(id: ObjectIdentifier(a), key: keyA)
        XCTAssertTrue(downA.commits.isEmpty)
        XCTAssertEqual(tracker.highlightedKeyIDs, ["a"])

        let downB = tracker.began(id: ObjectIdentifier(b), key: keyB)
        XCTAssertEqual(downB.commits.map(\.id), ["a"])
        XCTAssertEqual(tracker.highlightedKeyIDs, ["b"])

        let upA = tracker.ended(id: ObjectIdentifier(a), key: keyA)
        XCTAssertTrue(upA.commits.isEmpty)

        let upB = tracker.ended(id: ObjectIdentifier(b), key: keyB)
        XCTAssertEqual(upB.commits.map(\.id), ["b"])
        XCTAssertTrue(tracker.highlightedKeyIDs.isEmpty)
    }

    func testShiftHoldWithOtherFingerDoesNotCommitShift() {
        let tracker = TypingTouchTracker()
        let shiftFinger = Token()
        let letterFinger = Token()
        let shift = shiftKey()
        let keyA = letter("a")

        let downShift = tracker.began(id: ObjectIdentifier(shiftFinger), key: shift)
        XCTAssertTrue(downShift.beginShift)
        XCTAssertTrue(downShift.commits.isEmpty)

        let downA = tracker.began(id: ObjectIdentifier(letterFinger), key: keyA)
        XCTAssertTrue(downA.commits.isEmpty)
        XCTAssertFalse(downA.beginShift)

        let upA = tracker.ended(id: ObjectIdentifier(letterFinger), key: keyA)
        XCTAssertEqual(upA.commits.map(\.id), ["a"])
        XCTAssertFalse(upA.endShift)

        let upShift = tracker.ended(id: ObjectIdentifier(shiftFinger), key: shift)
        XCTAssertTrue(upShift.endShift)
        XCTAssertTrue(upShift.commits.isEmpty)
    }

    func testSlideReselectsWithoutCommittingPreviousKey() {
        let tracker = TypingTouchTracker()
        let finger = Token()
        let keyA = letter("a")
        let keyS = letter("s")

        _ = tracker.began(id: ObjectIdentifier(finger), key: keyA)
        let moved = tracker.moved(id: ObjectIdentifier(finger), key: keyS)
        XCTAssertTrue(moved.commits.isEmpty)
        XCTAssertEqual(moved.playFeedback?.id, "s")
        XCTAssertEqual(tracker.highlightedKeyIDs, ["s"])

        let ended = tracker.ended(id: ObjectIdentifier(finger), key: keyS)
        XCTAssertEqual(ended.commits.map(\.id), ["s"])
    }

    func testLiftOutsideCancelsPendingKey() {
        let tracker = TypingTouchTracker()
        let finger = Token()
        _ = tracker.began(id: ObjectIdentifier(finger), key: letter("a"))
        let ended = tracker.ended(id: ObjectIdentifier(finger), key: nil)
        XCTAssertTrue(ended.commits.isEmpty)
    }

    func testCancelDoesNotCommit() {
        let tracker = TypingTouchTracker()
        let finger = Token()
        _ = tracker.began(id: ObjectIdentifier(finger), key: letter("a"))
        let cancelled = tracker.cancelled(id: ObjectIdentifier(finger))
        XCTAssertTrue(cancelled.commits.isEmpty)
        XCTAssertTrue(tracker.highlightedKeyIDs.isEmpty)
    }

    func testLetterWhileDeletingStopsRepeat() {
        let tracker = TypingTouchTracker()
        let delFinger = Token()
        let letterFinger = Token()

        let downDelete = tracker.began(id: ObjectIdentifier(delFinger), key: deleteKey())
        XCTAssertTrue(downDelete.deleteFire)
        XCTAssertTrue(downDelete.startDeleteRepeat)

        let downLetter = tracker.began(id: ObjectIdentifier(letterFinger), key: letter("a"))
        XCTAssertTrue(downLetter.stopDeleteRepeat)
        XCTAssertFalse(downLetter.deleteFire)
        XCTAssertTrue(downLetter.commits.isEmpty)
    }

    func testSecondFingerOnSameKeyIsIgnored() {
        let tracker = TypingTouchTracker()
        let first = Token()
        let second = Token()
        let keyA = letter("a")

        _ = tracker.began(id: ObjectIdentifier(first), key: keyA)
        let duplicate = tracker.began(id: ObjectIdentifier(second), key: keyA)
        XCTAssertTrue(duplicate.commits.isEmpty)
        XCTAssertNil(duplicate.playFeedback)

        let upFirst = tracker.ended(id: ObjectIdentifier(first), key: keyA)
        XCTAssertEqual(upFirst.commits.map(\.id), ["a"])
        let upSecond = tracker.ended(id: ObjectIdentifier(second), key: keyA)
        XCTAssertTrue(upSecond.commits.isEmpty)
    }
}
