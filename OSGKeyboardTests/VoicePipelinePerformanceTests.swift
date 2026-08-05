// VoicePipelinePerformanceTests.swift
// OSGKeyboardTests
//
// Hermetic performance coverage for voice → ASR → guard → polish → bridge.
// Stub ASR/LLM + synthetic PCM (no mic / no live network).
// Run: ./Scripts/run-tests.sh perf

import XCTest
@testable import OSGKeyboardShared
@testable import OSGKeyboardHostSupport

final class VoicePipelinePerformanceTests: XCTestCase {

    /// Generous CI ceilings for stubbed work (not device mic/ASR SLAs).
    private enum SLA {
        static let pcmFeed: TimeInterval = 0.050
        static let chunkASRIdle: TimeInterval = 0.750
        static let transcriptGuard: TimeInterval = 0.020
        static let polishIdle: TimeInterval = 0.750
        static let bridgeDeliver: TimeInterval = 0.100
        static let totalE2EIdle: TimeInterval = 1.500
        /// Injected 40ms ASR delay must land in chunk_asr (±25ms).
        static let injectedDelayTolerance: TimeInterval = 0.025
    }

    func testEndToEndStageTimingsUnderStubSLA() async throws {
        let timings = try await VoicePipelinePerfHarness.run()
        attachReport(timings, name: "e2e-idle")

        XCTAssertFalse(timings.asrText.isEmpty)
        XCTAssertEqual(timings.polishedText, "今天部署已经全部完成。")
        XCTAssertEqual(timings.deliveredText, timings.polishedText)

        XCTAssertLessThan(timings.pcmFeedSeconds, SLA.pcmFeed, "pcm_feed")
        XCTAssertLessThan(timings.chunkASRSeconds, SLA.chunkASRIdle, "chunk_asr")
        XCTAssertLessThan(timings.transcriptGuardSeconds, SLA.transcriptGuard, "transcript_guard")
        XCTAssertLessThan(timings.polishSeconds, SLA.polishIdle, "polish")
        XCTAssertLessThan(timings.bridgeDeliverSeconds, SLA.bridgeDeliver, "bridge_deliver")
        XCTAssertLessThan(timings.totalSeconds, SLA.totalE2EIdle, "total_e2e")

        // Stage sum (excluding total) should not exceed total by much.
        let staged =
            timings.pcmFeedSeconds
            + timings.chunkASRSeconds
            + timings.transcriptGuardSeconds
            + timings.batchFallbackSeconds
            + timings.polishSeconds
            + timings.bridgeDeliverSeconds
        XCTAssertLessThanOrEqual(staged, timings.totalSeconds + 0.005)
    }

    func testChunkASRStageReflectsInjectedASRDelay() async throws {
        let delayNs: UInt64 = 40_000_000 // 40 ms
        let timings = try await VoicePipelinePerfHarness.run(
            config: .init(asrDelayNanoseconds: delayNs)
        )
        attachReport(timings, name: "asr-delay-40ms")

        let expected = Double(delayNs) / 1e9
        XCTAssertGreaterThan(
            timings.chunkASRSeconds,
            expected - SLA.injectedDelayTolerance,
            "chunk_asr should include injected ASR delay"
        )
        XCTAssertGreaterThan(
            timings.chunkASRSeconds,
            timings.polishSeconds,
            "with ASR delay, chunk_asr should dominate polish"
        )
    }

    func testPolishStageReflectsInjectedLLMDelay() async throws {
        let delayNs: UInt64 = 50_000_000 // 50 ms
        let timings = try await VoicePipelinePerfHarness.run(
            config: .init(polishDelayNanoseconds: delayNs)
        )
        attachReport(timings, name: "polish-delay-50ms")

        let expected = Double(delayNs) / 1e9
        XCTAssertGreaterThan(
            timings.polishSeconds,
            expected - SLA.injectedDelayTolerance,
            "polish should include injected LLM delay"
        )
    }

    func testBatchFallbackStageAppearsWhenPartialWins() async throws {
        let longPartial = String(repeating: "部", count: 40)
        let timings = try await VoicePipelinePerfHarness.run(
            config: .init(
                asrTranscript: "短",
                polishedTranscript: longPartial,
                partialSnapshotOverride: longPartial,
                batchTranscript: longPartial + "批",
                runBatchFallbackIfNeeded: true
            )
        )
        attachReport(timings, name: "batch-fallback")

        XCTAssertTrue(timings.didRunBatchFallback)
        XCTAssertGreaterThan(timings.batchFallbackSeconds, 0)
        XCTAssertFalse(timings.deliveredText.isEmpty)
    }

    func testIndividualStagesRemainMeasurableInIsolation() async throws {
        // Chunker + stub ASR only (no polish/bridge) — smoke that pcm→text stays fast.
        let samples = SyntheticPCM.tone(durationSeconds: 0.2, sampleRate: 1_000)
        let stream = SyntheticPCM.stream(samples: samples, sampleRate: 1_000)
        let asr = TimedStubChunkASR(transcript: "隔离ASR")
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: FlowUtteranceChunkConfig(
                maxChunkDurationSeconds: 0.05,
                overlapDurationSeconds: 0,
                pauseExtensionMaxSeconds: 0,
                pauseRMSThreshold: 1.0,
                minFinalChunkDurationSeconds: 0.05,
                sampleRate: 1_000
            )
        )

        let start = ContinuousClock.now
        let outcome = await pipeline.transcribe(stream: stream) { _ in }
        let elapsed = elapsedSeconds(since: start)

        guard case .success(let success) = outcome else {
            return XCTFail("expected ASR success")
        }
        XCTAssertTrue(success.text.contains("隔离ASR"))
        XCTAssertLessThan(elapsed, SLA.chunkASRIdle)
    }

    // MARK: - Helpers

    private func attachReport(_ timings: VoicePipelineStageTimings, name: String) {
        let text = timings.reportText()
        // Surfaces in the test report navigator / xcresult.
        let attachment = XCTAttachment(string: text)
        attachment.name = "voice-pipeline-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(text)
    }

    private func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
}
