// ProgressiveDictationTranscriptAccumulatorTests.swift
// OSGKeyboardTests

import CoreMedia
import XCTest
@testable import OSGKeyboardShared

final class ProgressiveDictationTranscriptAccumulatorTests: XCTestCase {

    private func range(start: Double, duration: Double = 30) -> CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
    }

    func testCumulativePartialsWithinSameRangeUpdateSegment() {
        var acc = ProgressiveDictationTranscriptAccumulator()
        let r0 = range(start: 0)

        XCTAssertEqual(acc.ingest(range: r0, text: "今天天气"), "今天天气")
        XCTAssertEqual(acc.ingest(range: r0, text: "今天天气很好"), "今天天气很好")
        XCTAssertEqual(acc.finalize(), "今天天气很好")
    }

    func testNewRangeAppendsInsteadOfReplacingEarlierSpeech() {
        var acc = ProgressiveDictationTranscriptAccumulator()
        let r0 = range(start: 0)
        let r30 = range(start: 30)

        _ = acc.ingest(range: r0, text: "前三十秒的内容")
        _ = acc.ingest(range: r30, text: "后二十秒的内容")

        XCTAssertEqual(acc.finalize(), "前三十秒的内容 后二十秒的内容")
    }

    func testDuplicateEmissionIsSuppressed() {
        var acc = ProgressiveDictationTranscriptAccumulator()
        let r0 = range(start: 0)

        XCTAssertNotNil(acc.ingest(range: r0, text: "hello"))
        XCTAssertNil(acc.ingest(range: r0, text: "hello"))
    }
}
