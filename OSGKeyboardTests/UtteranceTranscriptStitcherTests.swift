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

    func testComposedSafelyFallsBackWhenOverlapMergeShortensTooMuch() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 0, text: "今天天气很好我们")
        stitcher.append(index: 1, text: "去公园")
        let merged = stitcher.composed()
        let safe = stitcher.composedSafely()
        XCTAssertFalse(merged.isEmpty)
        XCTAssertFalse(safe.isEmpty)
        XCTAssertTrue(safe.contains("去公园"))
    }

    func testRemoveLastSegmentSupportsMergedTailRetranscription() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 0, text: "第一段")
        stitcher.append(index: 1, text: "第二段")
        stitcher.removeLastSegment()
        stitcher.append(index: 1, text: "第二段合并")
        XCTAssertEqual(stitcher.composed(), "第一段 第二段合并")
    }
}
