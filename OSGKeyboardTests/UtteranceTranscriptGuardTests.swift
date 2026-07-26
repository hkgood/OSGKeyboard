// UtteranceTranscriptGuardTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class UtteranceTranscriptGuardTests: XCTestCase {

    func testResolvePrefersPartialWhenClearlyLonger() {
        let resolved = UtteranceTranscriptGuard.resolve(
            stitchedFinal: "今天天气很好",
            partialSnapshot: "今天天气很好，我们一起去公园吧"
        )
        XCTAssertEqual(resolved, "今天天气很好，我们一起去公园吧")
    }

    func testResolveKeepsFinalWhenPartialIsNotLonger() {
        let resolved = UtteranceTranscriptGuard.resolve(
            stitchedFinal: "今天天气很好，我们一起去公园吧",
            partialSnapshot: "今天天气很好"
        )
        XCTAssertEqual(resolved, "今天天气很好，我们一起去公园吧")
    }

    func testResolveUsesPartialWhenFinalEmpty() {
        let resolved = UtteranceTranscriptGuard.resolve(
            stitchedFinal: "",
            partialSnapshot: "最后一段 partial"
        )
        XCTAssertEqual(resolved, "最后一段 partial")
    }
}
