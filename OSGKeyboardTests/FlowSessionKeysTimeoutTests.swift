// FlowSessionKeysTimeoutTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowSessionKeysTimeoutTests: XCTestCase {

    func testKeyboardASRPhaseTimeoutShorterThanFullResultTimeout() {
        for mode in ["local", "cloud"] {
            let asrPhase = FlowSessionKeys.keyboardASRPhaseTimeout(engineMode: mode)
            let full = FlowSessionKeys.keyboardResultTimeout(engineMode: mode)
            XCTAssertLessThan(asrPhase, full)
            XCTAssertEqual(
                asrPhase,
                (mode == "local"
                    ? FlowSessionKeys.localASRWaitTimeout
                    : FlowSessionKeys.cloudASRWaitTimeout)
                    + FlowSessionKeys.resultDeliveryMargin
            )
        }
    }
}
