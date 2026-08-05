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
        let rows = layout.rows(for: .letters, language: .english, shiftActive: false)
        XCTAssertEqual(rows.first, ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
        let shifted = layout.rows(for: .letters, language: .english, shiftActive: true)
        XCTAssertEqual(shifted.first?.first, "Q")
    }

    func testEnglishNumberAndSymbolPagesMatchIOSUS() {
        let layout = StandardTypingLayout()
        XCTAssertEqual(
            layout.rows(for: .numbers, language: .english, shiftActive: false),
            [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                ["#+=", ".", ",", "?", "!", "'", "⌫"]
            ]
        )
        XCTAssertEqual(
            layout.rows(for: .symbols, language: .english, shiftActive: false),
            [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
                ["123", ".", ",", "?", "!", "'", "⌫"]
            ]
        )
    }

    func testChineseNumberAndSymbolPagesMatchIOSSimplified() {
        let layout = StandardTypingLayout()
        XCTAssertEqual(
            layout.rows(for: .numbers, language: .chinese, shiftActive: false),
            [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", "：", "；", "（", "）", "￥", "@", "“", "”"],
                ["#+=", "。", "，", "、", "？", "！", ".", "⌫"]
            ]
        )
        XCTAssertEqual(
            layout.rows(for: .symbols, language: .chinese, shiftActive: false),
            [
                ["【", "】", "「", "」", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "《", "》", "€", "£", "¥", "·"],
                ["123", "。", "，", "、", "？", "！", ".", "⌫"]
            ]
        )
    }

    func testKeyRowsFollowTypingLanguageOnNumberPage() {
        let typing = TypingSessionController()
        typing.setPage(.numbers)
        XCTAssertEqual(typing.keyRows[1], ["-", "/", "：", "；", "（", "）", "￥", "@", "“", "”"])

        _ = typing.setLanguage(.english)
        typing.setPage(.numbers)
        XCTAssertEqual(typing.keyRows[1], ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
    }

    func testVoiceAndTypingChromeShareStableDimensions() {
        XCTAssertEqual(KeyboardChromeLayout.totalHeight, 281)
        XCTAssertEqual(KeyboardChromeLayout.actionKeyHeight, 50)
        XCTAssertEqual(KeyboardChromeLayout.actionKeyCornerRadius, 10)
        XCTAssertEqual(KeyboardChromeLayout.actionKeySpacing, 8)
        XCTAssertEqual(KeyboardChromeLayout.sideActionKeyFraction, 0.2)
        XCTAssertEqual(KeyboardChromeLayout.centerActionKeyFraction, 0.6)
        XCTAssertEqual(KeyboardChromeLayout.horizontalInset, 8)
        XCTAssertEqual(KeyboardChromeLayout.contentMaxWidth, 700)

        let widths = KeyboardChromeLayout.actionKeyWidths(availableWidth: 374)
        XCTAssertEqual(widths.side, 71.6, accuracy: 0.001)
        XCTAssertEqual(widths.center, 214.8, accuracy: 0.001)
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
        XCTAssertTrue(typing.isShiftEnabled)
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }

    func testManualShiftSurvivesAutocapitalizationSync() {
        let typing = TypingSessionController()
        // Providers must be set before language switch (which syncs autocap).
        typing.precedingTextProvider = { "hello " } // mid-sentence: auto stays off
        typing.autocapitalizationModeProvider = { .sentences }
        _ = typing.setLanguage(.english)
        XCTAssertFalse(typing.shiftActive)

        _ = typing.handleKey("⇧")
        XCTAssertTrue(typing.shiftActive)

        typing.syncAutocapitalization()
        XCTAssertTrue(typing.shiftActive, "manual one-shot must outrank autocap sync")
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }

    func testShiftHoldTypesUppercaseWithoutEnteringCapsLock() {
        let typing = TypingSessionController()
        _ = typing.setLanguage(.english)
        typing.precedingTextProvider = { "hello " }
        typing.autocapitalizationModeProvider = { .sentences }

        typing.beginShiftHold()
        XCTAssertTrue(typing.shiftHeld)
        XCTAssertEqual(typing.keyRows.first?.first, "Q")

        _ = typing.handleKey("S")
        _ = typing.handleKey("m")
        XCTAssertFalse(typing.capsLock)

        typing.endShiftHold()
        XCTAssertFalse(typing.shiftHeld)
        XCTAssertFalse(typing.capsLock)
        XCTAssertFalse(typing.shiftActive)
    }

    func testShiftHoldWithoutTypingActsAsTap() {
        let typing = TypingSessionController()
        typing.beginShiftHold()
        typing.endShiftHold()
        XCTAssertTrue(typing.shiftActive)
        XCTAssertFalse(typing.shiftHeld)
        XCTAssertFalse(typing.capsLock)
    }
}
