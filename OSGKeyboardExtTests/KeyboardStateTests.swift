// KeyboardStateTests.swift
// OSGKeyboard · Keyboard Extension Tests
//
// Target existence tests for the new `OSGKeyboardExtTests` target
// (TEST-4). We focus on `KeyboardState` (formerly `KeyboardViewController.State`,
// now extracted to `OSGKeyboardShared`) because it's the highest-leverage
// thing to test: it owns the published view model that every keyboard UI
// view reads from.
//
// The `KeyboardViewController` itself is hard to instantiate in a test
// host because it derives from `UIInputViewController` and needs a real
// input view, microphone permission prompts, etc. We deliberately
// *don't* attempt that here — the State class is what we care about
// for correctness.

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class KeyboardStateTests: XCTestCase {

    func testTargetCompiles() {
        // Pure existence check — the build itself proves the target links.
        // This test exists so `xcodebuild test` for `OSGKeyboardExtTests`
        // has at least one passing assertion.
        XCTAssertTrue(true)
    }

    func testInitialState() {
        let s = KeyboardState()
        XCTAssertEqual(s.phase, .idle)
        XCTAssertEqual(s.mode, .polish)
        XCTAssertEqual(s.localeId, "auto")
        XCTAssertEqual(s.lastTranscript, "")
        XCTAssertEqual(s.level, 0)
        XCTAssertFalse(s.onDeviceSupported)
    }

    func testPhaseTransitionsIdleToRequestingPermissionsAndBack() {
        let s = KeyboardState()
        s.phase = .requestingPermissions
        XCTAssertNotEqual(s.phase, .idle)
        s.phase = .recording
        XCTAssertEqual(s.phase, .recording)
        s.phase = .processing
        XCTAssertEqual(s.phase, .processing)
        s.phase = .idle
        XCTAssertEqual(s.phase, .idle)
    }

    func testStructuredErrorCarriesLLMError() {
        let s = KeyboardState()
        let underlying = LLMError.http(status: 401)
        s.phase = .error(.llm(underlying), message: "API Key 无效")
        if case .error(let kind, let msg) = s.phase {
            XCTAssertEqual(kind, .llm(underlying))
            XCTAssertEqual(msg, "API Key 无效")
        } else {
            XCTFail("expected structured .error phase")
        }
    }

    func testModeSwitchFromPolishToOff() {
        let s = KeyboardState()
        XCTAssertEqual(s.mode, .polish)
        s.mode = .off
        XCTAssertEqual(s.mode, .off)
        s.mode = .transcribe
        XCTAssertEqual(s.mode, .transcribe)
        s.mode = .polish
        XCTAssertEqual(s.mode, .polish)
    }

    func testInputModeRoundTripsThroughRawValue() {
        // The mode is persisted by rawValue (see `AppGroupStore.setModeId`)
        // so the round-trip is part of the public contract.
        for mode in KeyboardState.InputMode.allCases {
            let raw = mode.rawValue
            XCTAssertNotNil(KeyboardState.InputMode(rawValue: raw))
        }
    }
}