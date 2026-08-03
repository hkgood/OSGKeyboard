// KeyboardSurfaceStateTests.swift
// OSGKeyboard · Ext unit tests

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class KeyboardSurfaceStateTests: XCTestCase {
    func testRecordingLocksTyping() {
        let state = KeyboardState()
        state.phase = .idle
        XCTAssertTrue(state.canEnterTypingSurface)
        state.phase = .recording
        XCTAssertTrue(state.locksTypingSurface)
        XCTAssertFalse(state.canEnterTypingSurface)
    }

    func testStandardLayoutHasQwertyTopRow() {
        let layout = StandardTypingLayout()
        let rows = layout.rows(for: .letters, shiftActive: false)
        XCTAssertEqual(rows.first, ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
        let shifted = layout.rows(for: .letters, shiftActive: true)
        XCTAssertEqual(shifted.first?.first, "Q")
    }

    func testVoiceAndTypingChromeShareStableDimensions() {
        XCTAssertEqual(KeyboardChromeLayout.totalHeight, 281)
        XCTAssertEqual(KeyboardChromeLayout.actionKeyHeight, 50)
        XCTAssertEqual(KeyboardChromeLayout.actionKeyCornerRadius, 10)
        XCTAssertEqual(KeyboardChromeLayout.sideActionKeyWidth, 86)
        XCTAssertEqual(KeyboardChromeLayout.horizontalInset, 8)
    }

    func testSharedCapsuleCanSelectSpecificTypingLanguage() {
        let typing = TypingSessionController()
        XCTAssertEqual(typing.language, .chinese)

        XCTAssertEqual(typing.setLanguage(.english), .none)
        XCTAssertEqual(typing.language, .english)

        XCTAssertEqual(typing.setLanguage(.chinese), .none)
        XCTAssertEqual(typing.language, .chinese)
    }

    func testShiftStateProducesUppercaseKeyRows() {
        let typing = TypingSessionController()
        XCTAssertFalse(typing.shiftActive)

        _ = typing.handleKey("⇧")

        XCTAssertTrue(typing.shiftActive)
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }
}
