// KeyboardTextInserterLogicTests.swift
// OSGKeyboardTests
//
// KeyboardTextInserter lives in the app extension and cannot be linked from
// unit tests, so we verify the empty-transcript contract via shared helpers.

import XCTest
@testable import OSGKeyboardShared

final class KeyboardTextInserterLogicTests: XCTestCase {

    func testEmptyFinalResultIsNotConsumable() {
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writeFinal(
            text: "   ",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1
        )
        let result = FlowSessionBridge.latestResult()
        XCTAssertFalse(KeyboardFlowResultMatcher.isConsumableFinal(result!))
        XCTAssertEqual(
            KeyboardFlowResultConsumer.evaluate(
                latestResult: result,
                activeSessionId: sessionId,
                currentUtteranceId: utteranceId
            ),
            .none
        )
    }
}
