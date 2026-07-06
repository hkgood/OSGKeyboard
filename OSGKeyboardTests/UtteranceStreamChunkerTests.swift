// UtteranceStreamChunkerTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class UtteranceStreamChunkerTests: XCTestCase {

    private let config = FlowUtteranceChunkConfig(
        maxChunkDurationSeconds: 1,
        overlapDurationSeconds: 0.1,
        pauseExtensionMaxSeconds: 0.2,
        pauseRMSThreshold: 0.02,
        sampleRate: 1_000
    )

    func testPauseAwareSplitPrefersSilenceNearWindowEnd() {
        var buffer = [Float](repeating: 0.2, count: 900)
        buffer.append(contentsOf: [Float](repeating: 0.001, count: 50))
        buffer.append(contentsOf: [Float](repeating: 0.2, count: 100))

        let split = UtteranceStreamChunker.pauseAwareSplitIndex(in: buffer, config: config)
        XCTAssertGreaterThanOrEqual(split, config.maxChunkSamples)
        XCTAssertLessThanOrEqual(split, config.maxChunkSamples + config.pauseExtensionSamples)
    }

    func testFirstChunkUsesShorterWindow() async {
        let config = FlowUtteranceChunkConfig(
            firstChunkDurationSeconds: 0.5,
            subsequentChunkDurationSeconds: 1.0,
            overlapDurationSeconds: 0,
            pauseExtensionMaxSeconds: 0,
            pauseRMSThreshold: 0.02,
            sampleRate: 1_000
        )
        let firstChunkSamples = config.maxChunkSamples(forChunkIndex: 0) + 50
        let samples = [Float](repeating: 0.05, count: firstChunkSamples)
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: samples, sampleRate: Double(config.sampleRate)))
        continuation.finish()

        var received: [UtteranceAudioChunk] = []
        for await chunk in UtteranceStreamChunker.chunks(from: stream, config: config) {
            received.append(chunk)
        }

        XCTAssertGreaterThanOrEqual(received.count, 2)
        XCTAssertLessThanOrEqual(received[0].samples.count, config.maxChunkSamples(forChunkIndex: 0) + 50)
    }

    func testChunksEmitMultipleSegmentsForLongStream() async {
        let sampleCount = config.maxChunkSamples * 2 + 100
        let samples = [Float](repeating: 0.05, count: sampleCount)
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: samples, sampleRate: Double(config.sampleRate)))
        continuation.finish()

        var received: [UtteranceAudioChunk] = []
        for await chunk in UtteranceStreamChunker.chunks(from: stream, config: config) {
            received.append(chunk)
        }

        XCTAssertGreaterThanOrEqual(received.count, 2)
        XCTAssertTrue(received.last?.isLast == true)
    }
}
