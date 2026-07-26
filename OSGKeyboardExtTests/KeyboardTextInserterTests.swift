// KeyboardTextInserterTests.swift
// OSGKeyboardExtTests

import XCTest
@testable import OSGKeyboardExt
@testable import OSGKeyboardShared

@MainActor
final class KeyboardTextInserterTests: XCTestCase {

    func testEmptyTranscriptSurfacesNoSpeechError() {
        let state = KeyboardState()
        state.phase = .processing
        var inserted = ""
        let inserter = KeyboardTextInserter(
            state: state,
            insertText: { inserted = $0 },
            contextBeforeInput: { nil },
            scheduleAutoClearError: {}
        )

        inserter.handleFlowTranscript(TranscriptionDelivery(text: "   ", polishWarning: nil))

        XCTAssertEqual(inserted, "")
        if case .error(.noSpeechDetected, _) = state.phase {
            // expected
        } else {
            XCTFail("expected noSpeechDetected error phase")
        }
    }

    func testNonEmptyTranscriptInsertsWithSeparator() {
        let state = KeyboardState()
        var inserted = ""
        let inserter = KeyboardTextInserter(
            state: state,
            insertText: { inserted = $0 },
            contextBeforeInput: { "Hello" },
            scheduleAutoClearError: {}
        )

        inserter.handleFlowTranscript(TranscriptionDelivery(text: "world", polishWarning: nil))

        XCTAssertEqual(inserted, " world")
        XCTAssertEqual(state.phase, .idle)
    }
}
