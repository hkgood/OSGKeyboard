// UtteranceBatchFallbackPolicyTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class UtteranceBatchFallbackPolicyTests: XCTestCase {

    func testShouldRunWhenPartialClearlyLonger() {
        XCTAssertTrue(
            UtteranceBatchFallbackPolicy.shouldRunBatchFallback(
                stitchedFinal: "今天很好",
                partialSnapshot: "今天很好，我们一起去公园吧"
            )
        )
    }

    func testShouldRunWhenFinalEmptyButPartialPresent() {
        XCTAssertTrue(
            UtteranceBatchFallbackPolicy.shouldRunBatchFallback(
                stitchedFinal: "",
                partialSnapshot: "最后一段"
            )
        )
    }

    func testShouldNotRunWhenPartialNotLonger() {
        XCTAssertFalse(
            UtteranceBatchFallbackPolicy.shouldRunBatchFallback(
                stitchedFinal: "今天很好，我们一起去公园吧",
                partialSnapshot: "今天很好"
            )
        )
    }

    func testShouldRunAfterRecognitionFailureEvenWithRecoveredPartial() {
        XCTAssertTrue(
            UtteranceBatchFallbackPolicy.shouldRunBatchFallback(
                stitchedFinal: "恢复出的局部文本",
                partialSnapshot: "恢复出的局部文本",
                recognitionFailed: true
            )
        )
    }

    func testPreferredTranscriptPicksLongestCandidate() {
        let resolved = UtteranceBatchFallbackPolicy.preferredTranscript(
            batch: "今天很好，我们一起去公园吧",
            stitchedFinal: "今天很好",
            partialSnapshot: "今天很好，我们",
            current: "今天很好，我们"
        )
        XCTAssertEqual(resolved, "今天很好，我们一起去公园吧")
    }
}
