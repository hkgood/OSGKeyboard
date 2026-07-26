// KeyboardFlowResultMatcherTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class KeyboardFlowResultMatcherTests: XCTestCase {

    private func makeResult(
        sessionId: UUID,
        utteranceId: UUID,
        status: FlowResult.Status,
        text: String? = "hello"
    ) -> FlowResult {
        FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            status: status,
            text: text
        )
    }

    func testMatchingResultRequiresSessionAndUtterance() {
        let sessionId = UUID()
        let utteranceId = UUID()
        let result = makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .final)
        XCTAssertEqual(
            KeyboardFlowResultMatcher.matchingResult(
                latest: result,
                activeSessionId: sessionId,
                currentUtteranceId: utteranceId
            ),
            result
        )
        XCTAssertNil(
            KeyboardFlowResultMatcher.matchingResult(
                latest: result,
                activeSessionId: UUID(),
                currentUtteranceId: utteranceId
            )
        )
        XCTAssertNil(
            KeyboardFlowResultMatcher.matchingResult(
                latest: result,
                activeSessionId: sessionId,
                currentUtteranceId: UUID()
            )
        )
    }

    func testIsTerminalFailure() {
        let sessionId = UUID()
        let utteranceId = UUID()
        XCTAssertTrue(
            KeyboardFlowResultMatcher.isTerminalFailure(
                makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .error, text: "fail")
            )
        )
        XCTAssertTrue(
            KeyboardFlowResultMatcher.isTerminalFailure(
                makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .timeout, text: "t")
            )
        )
        XCTAssertFalse(
            KeyboardFlowResultMatcher.isTerminalFailure(
                makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .final)
            )
        )
    }

    func testIsConsumableFinalRejectsEmptyText() {
        let sessionId = UUID()
        let utteranceId = UUID()
        XCTAssertTrue(
            KeyboardFlowResultMatcher.isConsumableFinal(
                makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .final, text: "ok")
            )
        )
        XCTAssertFalse(
            KeyboardFlowResultMatcher.isConsumableFinal(
                makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .final, text: "  ")
            )
        )
        XCTAssertFalse(
            KeyboardFlowResultMatcher.isConsumableFinal(
                makeResult(sessionId: sessionId, utteranceId: utteranceId, status: .partial, text: "ok")
            )
        )
    }
}
