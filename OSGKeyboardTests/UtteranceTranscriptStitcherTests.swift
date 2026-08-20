// UtteranceTranscriptStitcherTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class UtteranceTranscriptStitcherTests: XCTestCase {

    func testMergeWithOverlapRemovesDuplicatedSuffixPrefix() {
        let merged = UtteranceTranscriptStitcher.mergeWithOverlap(
            previous: "今天天气很好",
            next: "很好我们继续"
        )
        XCTAssertEqual(merged, "今天天气很好我们继续")
    }

    func testNormalizedOverlapMapsThroughRawPunctuation() {
        let merged = UtteranceTranscriptStitcher.mergeWithOverlap(
            previous: "先这样用着，就算目前的可用性已经",
            next: "可用性，已经提升很多了"
        )
        XCTAssertEqual(merged, "先这样用着，就算目前的可用性已经提升很多了")
    }

    func testSingleCharacterOverlapRemainsStitcherSpecific() {
        XCTAssertEqual(
            UtteranceTranscriptStitcher.mergeWithOverlap(previous: "版本A", next: "A继续"),
            "版本A继续"
        )
    }

    func testStitcherOrdersChunksByIndex() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 1, text: "第二段")
        stitcher.append(index: 0, text: "第一段")
        XCTAssertEqual(stitcher.composed(), "第一段第二段")
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
        XCTAssertEqual(stitcher.composed(), "第一段第二段合并")
    }

    func testComposedWithPauseMarksInsertsAboveThreshold() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 0, text: "第一段", trailingPauseSeconds: 0.8)
        stitcher.append(index: 1, text: "第二段")
        XCTAssertEqual(stitcher.composedWithPauseMarks(), "第一段 ⟨0.8s⟩ 第二段")
    }

    func testComposedSafelyRemainsMarkerFree() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 0, text: "第一段", trailingPauseSeconds: 0.8)
        stitcher.append(index: 1, text: "第二段")
        XCTAssertFalse(stitcher.composedSafely().contains("⟨"))
    }

    /// Documents the preMerge wipe hazard: append ignores empty text, so
    /// removeLast + empty append leaves nothing. Pipeline must guard this.
    func testEmptyAppendAfterRemoveLastWipesPriorSegment() {
        var stitcher = UtteranceTranscriptStitcher()
        stitcher.append(index: 0, text: "已识别内容")
        stitcher.removeLastSegment()
        stitcher.append(index: 0, text: "")
        XCTAssertEqual(stitcher.composedSafely(), "")
    }
}
