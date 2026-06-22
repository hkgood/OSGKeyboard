// UtteranceTranscriptStitcherTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class UtteranceTranscriptStitcherTests: XCTestCase {

    func testMergeWithOverlapRemovesDuplicatedSuffixPrefix() {
        let merged = UtteranceTranscriptStitcher.mergeWithOverlap(
            previous: "今天天气很好",
            next: "很好我们继续"
        )
        XCTAssertEqual(merged, "今天天气很好我们继续")
    }

    func testStitcherOrdersChunksByIndex() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 1, text: "第二段")
        stitcher.append(index: 0, text: "第一段")
        XCTAssertEqual(stitcher.composed(), "第一段 第二段")
    }
}
