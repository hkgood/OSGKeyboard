// KeyboardTextInserterLogicTests.swift
// OSGKeyboardTests
//
// KeyboardTextInserter lives in the app extension and cannot be linked from
// unit tests, so we verify the empty-transcript contract via shared helpers.

import XCTest
@testable import OSGKeyboardShared

final class KeyboardTextInserterLogicTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.inserter.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testEmptyFinalResultIsNotConsumable() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()

        // Production path: whitespace-only finals are never persisted.
        FlowResultDelivery.writeFinal(
            text: "   ",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            defaults: defaults
        )
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))

        // Defensive: an empty persisted final must not be inserted.
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: 2,
                status: .final,
                text: "   "
            ),
            defaults: defaults
        )
        let result = FlowSessionBridge.latestResult(defaults: defaults)
        XCTAssertNotNil(result)
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
