// FinalChunkRecoveryTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FinalChunkRecoveryTests: XCTestCase {

    private let config = FlowUtteranceChunkConfig(
        maxChunkDurationSeconds: 5.0,
        overlapDurationSeconds: 0.5,
        pauseExtensionMaxSeconds: 2,
        pauseRMSThreshold: 0.015,
        minFinalChunkDurationSeconds: 0.8,
        sampleRate: 16_000
    )

    func testPreMergePlanForShortFinalChunk() {
        let chunk = UtteranceAudioChunk(
            index: 1,
            samples: [Float](repeating: 0.1, count: 4_000),
            isLast: true
        )
        let previous = [Float](repeating: 0.2, count: 80_000)

        let plan = FinalChunkRecovery.preMergePlan(
            chunk: chunk,
            processedChunks: 2,
            previousChunkSamples: previous,
            config: config
        )

        XCTAssertNotNil(plan)
        XCTAssertGreaterThan(plan?.samples.count ?? 0, chunk.samples.count)
        XCTAssertEqual(plan?.stitchIndex, 0)
    }

    func testEmptyResultRetryPlanUsesOverlapWhenPriorChunkExists() {
        let chunk = UtteranceAudioChunk(
            index: 1,
            samples: [Float](repeating: 0.1, count: 20_000),
            isLast: true
        )
        let previous = [Float](repeating: 0.2, count: 80_000)

        let plan = FinalChunkRecovery.emptyResultRetryPlan(
            chunk: chunk,
            previousChunkSamples: previous,
            config: config,
            asrText: "  "
        )

        XCTAssertNotNil(plan)
        XCTAssertGreaterThan(plan?.samples.count ?? 0, chunk.samples.count)
    }

    func testEmptyResultRetryPlanRetriesSingleChunkSamples() {
        let chunk = UtteranceAudioChunk(
            index: 0,
            samples: [Float](repeating: 0.1, count: 20_000),
            isLast: true
        )

        let plan = FinalChunkRecovery.emptyResultRetryPlan(
            chunk: chunk,
            previousChunkSamples: [],
            config: config,
            asrText: ""
        )

        XCTAssertEqual(plan?.samples.count, chunk.samples.count)
        XCTAssertEqual(plan?.stitchIndex, 0)
    }
}
