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

    func testFlowStructuredErrorKinds() {
        let s = KeyboardState()
        s.phase = .error(.manualOpenRequired, message: "open app")
        if case .error(.manualOpenRequired, let msg) = s.phase {
            XCTAssertEqual(msg, "open app")
        } else {
            XCTFail("expected manualOpenRequired")
        }

        s.phase = .error(.polishDegraded("warn"), message: "warn")
        if case .error(.polishDegraded("warn"), _) = s.phase {} else {
            XCTFail("expected polishDegraded")
        }

        s.phase = .error(.flowResultTimeout, message: "timeout")
        if case .error(.flowResultTimeout, _) = s.phase {} else {
            XCTFail("expected flowResultTimeout")
        }

        s.phase = .error(.flowSessionExpired, message: "expired")
        if case .error(.flowSessionExpired, _) = s.phase {} else {
            XCTFail("expected flowSessionExpired")
        }

        s.phase = .error(.fullAccessRequired, message: "full access")
        if case .error(.fullAccessRequired, _) = s.phase {} else {
            XCTFail("expected fullAccessRequired")
        }

        s.phase = .error(.noSpeechDetected, message: "no speech")
        if case .error(.noSpeechDetected, _) = s.phase {} else {
            XCTFail("expected noSpeechDetected")
        }

        s.phase = .error(.recognitionInterrupted, message: "interrupted")
        if case .error(.recognitionInterrupted, _) = s.phase {} else {
            XCTFail("expected recognitionInterrupted")
        }

        s.phase = .error(.hostAudioUnavailable, message: "audio")
        if case .error(.hostAudioUnavailable, _) = s.phase {} else {
            XCTFail("expected hostAudioUnavailable")
        }

        let flowError = FlowTranscriptionError(message: "asr failed", kind: .asrFailed)
        XCTAssertEqual(
            KeyboardState.Phase.ErrorKind.fromFlowTranscription(flowError),
            .hostTranscriptionFailed("asr failed")
        )
    }

    func testInputModeIsPolishOnly() {
        let s = KeyboardState()
        XCTAssertEqual(s.mode, .polish)
        XCTAssertEqual(KeyboardState.InputMode.allCases, [.polish])
        XCTAssertEqual(KeyboardState.InputMode(rawValue: "polish"), .polish)
    }
}
