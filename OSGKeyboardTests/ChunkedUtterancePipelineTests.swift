// ChunkedUtterancePipelineTests.swift
// OSGKeyboardExtTests
//
// Hostless Shared-pipeline tests (no OSGKeyboard.app TEST_HOST).
// Durations are seconds — at sampleRate 1000, 0.01s == 10 samples.

import XCTest
import os
@testable import OSGKeyboardShared
@testable import OSGKeyboardHostSupport

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

    /// 50-sample chunks @ 1 kHz; overlap / min-final expressed in seconds.
    private func config(
        maxChunkSeconds: TimeInterval = 0.05,
        overlapSeconds: TimeInterval = 0,
        minFinalSeconds: TimeInterval = 0.05
    ) -> FlowUtteranceChunkConfig {
        FlowUtteranceChunkConfig(
            maxChunkDurationSeconds: maxChunkSeconds,
            overlapDurationSeconds: overlapSeconds,
            pauseExtensionMaxSeconds: 0,
            pauseRMSThreshold: 1.0,
            minFinalChunkDurationSeconds: minFinalSeconds,
            sampleRate: 1_000
        )
    }

    func testPipelineStitchesQueuedChunks() async {
        let asr = StubChunkASR { samples in
            samples.isEmpty ? "" : "seg\(samples.count)"
        }
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: config(overlapSeconds: 0)
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.finish()

        let partialsLock = OSAllocatedUnfairLock(initialState: [String]())
        let outcome = await pipeline.transcribe(stream: stream) { partial in
            partialsLock.withLock { $0.append(partial) }
        }
        let partials = partialsLock.withLock { $0 }

        guard case .success(let success) = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertTrue(success.text.contains("seg"))
        XCTAssertFalse(partials.isEmpty)
    }

    func testPipelineRetriesTransientMiddleChunkFailure() async {
        let pipeline = ChunkedUtterancePipeline(
            asr: FailingSecondChunkASR(),
            locale: Locale(identifier: "zh-Hans"),
            config: config(overlapSeconds: 0)
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.finish()

        let outcome = await pipeline.transcribe(stream: stream) { _ in }

        guard case .success(let success) = outcome else {
            return XCTFail("expected partial success, got \(outcome)")
        }
        XCTAssertTrue(success.text.contains("recovered-middle"), "got \(success.text)")
        XCTAssertTrue(success.chunkWarnings.isEmpty)
    }

    func testPipelineWarnsAfterMiddleChunkRetryAlsoFails() async {
        let pipeline = ChunkedUtterancePipeline(
            asr: PermanentlyFailingMiddleChunkASR(),
            locale: Locale(identifier: "zh-Hans"),
            config: config(overlapSeconds: 0)
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(
            AudioBufferSnapshot(
                samples: [Float](repeating: 0.1, count: 160),
                sampleRate: 1_000
            )
        )
        continuation.finish()

        let outcome = await pipeline.transcribe(stream: stream) { _ in }
        guard case .success(let success) = outcome else {
            return XCTFail("expected partial success, got \(outcome)")
        }
        XCTAssertFalse(success.text.isEmpty)
        XCTAssertEqual(success.chunkWarnings.count, 1)
    }

    func testPipelineRetranscribesShortFinalChunkWithPriorOverlap() async {
        // overlap = 10 samples, minFinal = 50 samples @ 1 kHz
        let cfg = config(overlapSeconds: 0.01, minFinalSeconds: 0.05)
        XCTAssertEqual(cfg.overlapSamples, 10)
        XCTAssertEqual(cfg.minFinalChunkSamples, 50)

        let asr = ShortFinalMergeStubASR()
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: cfg
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        // 80 → emit 50 head; leftover 30. +20 → 50 exactly mid-chunk, then
        // empty last marker OR short tail via exact boundary — use 80+15 so
        // final leftover after mid split stays < minFinal.
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 15), sampleRate: 1_000))
        continuation.finish()

        let outcome = await pipeline.transcribe(stream: stream) { _ in }
        guard case .success(let success) = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertTrue(success.text.contains("merged"), "got \(success.text)")
    }

    func testPipelineRetriesEmptyFinalChunkWithOverlap() async {
        // Final chunk must be ≥ minFinal so emptyRetry runs (not preMerge).
        let cfg = config(overlapSeconds: 0.01, minFinalSeconds: 0.01)
        XCTAssertEqual(cfg.minFinalChunkSamples, 10)

        let asr = EmptyFinalRetryStubASR()
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: cfg
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.yield(AudioBufferSnapshot(samples: [Float](repeating: 0.1, count: 80), sampleRate: 1_000))
        continuation.finish()

        let outcome = await pipeline.transcribe(stream: stream) { _ in }
        guard case .success(let success) = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertTrue(success.text.contains("recovered-tail"), "got \(success.text)")
    }

    /// Deterministic AC327 regression: short final → preMerge → empty must keep "head".
    ///
    /// Layout @ 1 kHz:
    /// - maxChunk = 100, overlap = 20, minFinal = 80
    /// - yield 100 → chunk0 ASR "head"
    /// - yield 30 → final (30 < 80) → preMerge samples = 20+30
    func testPipelineKeepsPriorTextWhenPreMergeReturnsEmpty() async {
        let cfg = config(
            maxChunkSeconds: 0.1,
            overlapSeconds: 0.02,
            minFinalSeconds: 0.08
        )
        XCTAssertEqual(cfg.maxChunkSamples, 100)
        XCTAssertEqual(cfg.overlapSamples, 20)
        XCTAssertEqual(cfg.minFinalChunkSamples, 80)

        let asr = RecordingEmptyPreMergeASR()
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: cfg
        )

        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(
            AudioBufferSnapshot(samples: [Float](repeating: 0.2, count: 100), sampleRate: 1_000)
        )
        continuation.yield(
            AudioBufferSnapshot(samples: [Float](repeating: 0.2, count: 30), sampleRate: 1_000)
        )
        continuation.finish()

        let outcome = await pipeline.transcribe(stream: stream) { _ in }
        let sampleCounts = asr.sampleCountsSnapshot()

        guard case .success(let success) = outcome else {
            return XCTFail("expected success keeping prior text, got \(outcome); calls=\(sampleCounts)")
        }
        XCTAssertEqual(
            sampleCounts.count,
            2,
            "expected head chunk + one preMerge call, got \(sampleCounts)"
        )
        XCTAssertEqual(sampleCounts[0], 100)
        XCTAssertEqual(
            sampleCounts[1],
            50,
            "preMerge should be overlap(20)+tail(30), got \(sampleCounts[1])"
        )
        XCTAssertTrue(
            success.text.contains("head"),
            "empty preMerge must not wipe prior segment, got \(success.text)"
        )
        XCTAssertFalse(success.text.isEmpty)
    }
}

private struct FailingSecondChunkASR: ASRService, @unchecked Sendable {
    private let callIndex = OSAllocatedUnfairLock(initialState: 0)

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        let current = callIndex.withLock { state in
            let value = state
            state += 1
            return value
        }
        if current == 1 {
            return .failure("simulated chunk error")
        }
        if current == 2 {
            return .success("recovered-middle")
        }
        return .success("seg\(samples.count)")
    }
}

private struct PermanentlyFailingMiddleChunkASR: ASRService, @unchecked Sendable {
    private let callIndex = OSAllocatedUnfairLock(initialState: 0)

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        let current = callIndex.withLock { state in
            let value = state
            state += 1
            return value
        }
        if current == 1 || current == 2 {
            return .failure("persistent simulated chunk error")
        }
        return .success("seg\(samples.count)")
    }
}

private struct ShortFinalMergeStubASR: ASRService, @unchecked Sendable {
    private let callIndex = OSAllocatedUnfairLock(initialState: 0)

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        let current = callIndex.withLock { state in
            let value = state
            state += 1
            return value
        }
        if current == 0 {
            return .success("head")
        }
        // preMerge feeds overlap+tail (> first-pass short chunk size)
        if samples.count > 15 {
            return .success("merged-tail")
        }
        return .success("short")
    }
}

private struct EmptyFinalRetryStubASR: ASRService, @unchecked Sendable {
    private let callIndex = OSAllocatedUnfairLock(initialState: 0)

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        let current = callIndex.withLock { state in
            let value = state
            state += 1
            return value
        }
        if current == 0 {
            return .success("head")
        }
        if current == 1 {
            return .success("")
        }
        return .success("recovered-tail")
    }
}

/// Records sample counts; first call → "head", later calls → empty (preMerge wipe trap).
private final class RecordingEmptyPreMergeASR: ASRService, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Int]())

    func sampleCountsSnapshot() -> [Int] {
        lock.withLock { $0 }
    }

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        let callIndex = lock.withLock { state -> Int in
            state.append(samples.count)
            return state.count - 1
        }
        if callIndex == 0 {
            return .success("head")
        }
        return .success("")
    }
}
