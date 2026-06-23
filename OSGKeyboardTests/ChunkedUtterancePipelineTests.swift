// ChunkedUtterancePipelineTests.swift
// OSGKeyboardTests

import XCTest
import os
@testable import OSGKeyboardShared

private struct StubChunkASR: ASRService, @unchecked Sendable {
    let labels: @Sendable ([Float]) -> String

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        return .success(labels(samples))
    }
}

final class ChunkedUtterancePipelineTests: XCTestCase {

    func testPipelineStitchesQueuedChunks() async {
        let config = FlowUtteranceChunkConfig(
            maxChunkDurationSeconds: 0.05,
            overlapDurationSeconds: 0,
            pauseExtensionMaxSeconds: 0,
            pauseRMSThreshold: 0.02,
            sampleRate: 1_000
        )
        let asr = StubChunkASR { samples in
            samples.isEmpty ? "" : "seg\(samples.count)"
        }
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: config
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.finish()

        var partials: [String] = []
        let outcome = await pipeline.transcribe(stream: stream) { partial in
            partials.append(partial)
        }

        guard case .success(let success) = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertTrue(success.text.contains("seg"))
        XCTAssertFalse(partials.isEmpty)
    }

    func testPipelineDeliversPartialSuccessWhenOneChunkFails() async {
        let config = FlowUtteranceChunkConfig(
            maxChunkDurationSeconds: 0.05,
            overlapDurationSeconds: 0,
            pauseExtensionMaxSeconds: 0,
            pauseRMSThreshold: 0.02,
            sampleRate: 1_000
        )
        let pipeline = ChunkedUtterancePipeline(
            asr: FailingSecondChunkASR(),
            locale: Locale(identifier: "zh-Hans"),
            config: config
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.finish()

        let outcome = await pipeline.transcribe(stream: stream) { _ in }

        guard case .success(let success) = outcome else {
            return XCTFail("expected partial success, got \(outcome)")
        }
        XCTAssertFalse(success.text.isEmpty)
        XCTAssertEqual(success.chunkWarnings.count, 1)
    }
}

private struct FailingSecondChunkASR: ASRService, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var index = 0

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        let current = lock.withLock {
            defer { index += 1 }
            return index
        }
        if current == 1 {
            return .failure("simulated chunk error")
        }
        return .success("seg\(samples.count)")
    }
}
