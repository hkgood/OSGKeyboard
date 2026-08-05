// VoicePipelinePerfHarness.swift
// OSGKeyboardTests · TestSupport
//
// Hermetic voice → polish → bridge deliver harness with per-stage timings.
// No mic / no live network: synthetic PCM + stub ASR + injected LLM.

import Foundation
import os
@testable import OSGKeyboardShared
@testable import OSGKeyboardHostSupport

/// Wall-clock stage breakdown for one utterance finalize path.
struct VoicePipelineStageTimings: Sendable, Equatable {
    /// Build + yield synthetic PCM into an `AsyncStream`.
    var pcmFeedSeconds: TimeInterval = 0
    /// `ChunkedUtterancePipeline.transcribe` (chunk → ASR → stitch).
    var chunkASRSeconds: TimeInterval = 0
    /// `UtteranceTranscriptGuard.resolve`.
    var transcriptGuardSeconds: TimeInterval = 0
    /// Optional full-PCM batch ASR when policy fires.
    var batchFallbackSeconds: TimeInterval = 0
    /// `PolishingService.polishWithOutcome`.
    var polishSeconds: TimeInterval = 0
    /// App Group bridge write + keyboard-side match read-back.
    var bridgeDeliverSeconds: TimeInterval = 0
    /// End-to-end wall clock (pcm feed → bridge deliver).
    var totalSeconds: TimeInterval = 0

    var didRunBatchFallback: Bool = false
    var asrText: String = ""
    var guardedText: String = ""
    var polishedText: String = ""
    var deliveredText: String = ""

    /// Ordered rows for XCT attachments / console reports.
    var rows: [(stage: String, seconds: TimeInterval)] {
        var list: [(String, TimeInterval)] = [
            ("pcm_feed", pcmFeedSeconds),
            ("chunk_asr", chunkASRSeconds),
            ("transcript_guard", transcriptGuardSeconds),
        ]
        if didRunBatchFallback {
            list.append(("batch_fallback", batchFallbackSeconds))
        }
        list.append(contentsOf: [
            ("polish", polishSeconds),
            ("bridge_deliver", bridgeDeliverSeconds),
            ("total_e2e", totalSeconds),
        ])
        return list
    }

    func reportText() -> String {
        let body = rows
            .map { row in
                let ms = row.seconds * 1_000
                return "\(row.stage.padding(toLength: 18, withPad: " ", startingAt: 0)) \(String(format: "%8.3f", ms)) ms"
            }
            .joined(separator: "\n")
        return """
        Voice pipeline stage timings
        asr=\(asrText)
        guarded=\(guardedText)
        polished=\(polishedText)
        delivered=\(deliveredText)
        batch_fallback=\(didRunBatchFallback)
        ---
        \(body)
        """
    }
}

/// Deterministic non-silent PCM for chunker / RMS-style paths.
enum SyntheticPCM {
    static func tone(
        durationSeconds: TimeInterval,
        sampleRate: Double,
        amplitude: Float = 0.2,
        frequencyHz: Double = 440
    ) -> [Float] {
        let count = max(1, Int((durationSeconds * sampleRate).rounded()))
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            return amplitude * Float(sin(2 * Double.pi * frequencyHz * t))
        }
    }

    static func stream(
        samples: [Float],
        sampleRate: Double,
        frameSize: Int = 80
    ) -> AsyncStream<AudioBufferSnapshot> {
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        var index = 0
        while index < samples.count {
            let end = min(index + frameSize, samples.count)
            continuation.yield(
                AudioBufferSnapshot(
                    samples: Array(samples[index..<end]),
                    sampleRate: sampleRate
                )
            )
            index = end
        }
        continuation.finish()
        return stream
    }
}

/// Chunk ASR stub with optional per-chunk delay (for stage attribution).
struct TimedStubChunkASR: ASRChunkTranscribing, ASRService, @unchecked Sendable {
    let transcript: String
    let delayNanoseconds: UInt64
    let batchTranscript: String?
    /// Only the first non-empty chunk emits `transcript` so stitch stays short.
    private let emittedLock = OSAllocatedUnfairLock(initialState: false)

    init(
        transcript: String = "今天部署完成了",
        delayNanoseconds: UInt64 = 0,
        batchTranscript: String? = nil
    ) {
        self.transcript = transcript
        self.delayNanoseconds = delayNanoseconds
        self.batchTranscript = batchTranscript
    }

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func resetForNewUtterance() {
        emittedLock.withLock { $0 = false }
    }

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = locale
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if samples.isEmpty { return .success("") }
        // Full-utterance batch calls are much longer than a single chunk.
        if let batchTranscript, samples.count > 200 {
            return .success(batchTranscript)
        }
        let shouldEmit = emittedLock.withLock { emitted -> Bool in
            if emitted { return false }
            emitted = true
            return true
        }
        return .success(shouldEmit ? transcript : "")
    }
}

/// Injected polish client with optional delay.
final class TimedStubLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    let polished: String
    let delayNanoseconds: UInt64

    init(polished: String, delayNanoseconds: UInt64 = 0) {
        self.polished = polished
        self.delayNanoseconds = delayNanoseconds
    }

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        _ = text
        _ = systemPrompt
        _ = timeout
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return polished
    }
}

enum VoicePipelinePerfHarness {
    struct Config: Sendable {
        var sampleRate: Int = 1_000
        var utteranceDurationSeconds: TimeInterval = 0.25
        var asrTranscript: String = "今天部署完成了"
        var polishedTranscript: String = "今天部署已经全部完成。"
        var asrDelayNanoseconds: UInt64 = 0
        var polishDelayNanoseconds: UInt64 = 0
        /// When non-nil and longer than ASR text, forces guard/batch path.
        var partialSnapshotOverride: String? = nil
        var batchTranscript: String? = nil
        var runBatchFallbackIfNeeded: Bool = true
    }

    @MainActor
    static func run(config: Config = Config()) async throws -> VoicePipelineStageTimings {
        var timings = VoicePipelineStageTimings()
        let totalStart = ContinuousClock.now
        let rate = Double(config.sampleRate)

        let chunkConfig = FlowUtteranceChunkConfig(
            maxChunkDurationSeconds: 0.05,
            overlapDurationSeconds: 0,
            pauseExtensionMaxSeconds: 0,
            pauseRMSThreshold: 1.0,
            minFinalChunkDurationSeconds: 0.05,
            sampleRate: config.sampleRate
        )

        let asr = TimedStubChunkASR(
            transcript: config.asrTranscript,
            delayNanoseconds: config.asrDelayNanoseconds,
            batchTranscript: config.batchTranscript
        )

        // --- pcm_feed ---
        let pcmStart = ContinuousClock.now
        let samples = SyntheticPCM.tone(
            durationSeconds: config.utteranceDurationSeconds,
            sampleRate: rate
        )
        let stream = SyntheticPCM.stream(samples: samples, sampleRate: rate)
        timings.pcmFeedSeconds = elapsedSeconds(since: pcmStart)

        // --- chunk_asr ---
        let asrStart = ContinuousClock.now
        let partialsLock = OSAllocatedUnfairLock(initialState: "")
        let pipeline = ChunkedUtterancePipeline(
            asr: asr,
            locale: Locale(identifier: "zh-Hans"),
            config: chunkConfig
        )
        let outcome = await pipeline.transcribe(stream: stream) { partial in
            partialsLock.withLock { $0 = partial }
        }
        timings.chunkASRSeconds = elapsedSeconds(since: asrStart)

        let stitched: String
        switch outcome {
        case .success(let success):
            stitched = success.text
        case .cancelled:
            throw NSError(
                domain: "VoicePipelinePerfHarness",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "pipeline cancelled"]
            )
        case .failure(let message):
            throw NSError(
                domain: "VoicePipelinePerfHarness",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        timings.asrText = stitched

        let lastPartial = partialsLock.withLock { $0 }
        let partialSnapshot = config.partialSnapshotOverride ?? lastPartial

        // --- transcript_guard ---
        let guardStart = ContinuousClock.now
        var guarded = UtteranceTranscriptGuard.resolve(
            stitchedFinal: stitched,
            partialSnapshot: partialSnapshot
        )
        timings.transcriptGuardSeconds = elapsedSeconds(since: guardStart)
        timings.guardedText = guarded

        // --- batch_fallback (optional) ---
        if config.runBatchFallbackIfNeeded,
           UtteranceBatchFallbackPolicy.shouldRunBatchFallback(
               stitchedFinal: stitched,
               partialSnapshot: partialSnapshot
           ) {
            timings.didRunBatchFallback = true
            let batchStart = ContinuousClock.now
            let batch = await asr.transcribeChunk(samples: samples, locale: Locale(identifier: "zh-Hans"))
            let batchText: String
            if case .success(let text) = batch {
                batchText = text
            } else {
                batchText = ""
            }
            guarded = UtteranceBatchFallbackPolicy.preferredTranscript(
                batch: batchText,
                stitchedFinal: stitched,
                partialSnapshot: partialSnapshot,
                current: guarded
            )
            timings.batchFallbackSeconds = elapsedSeconds(since: batchStart)
            timings.guardedText = guarded
        }

        // --- polish ---
        let suiteName = "group.com.osgkeyboard.shared.tests.perf.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("local", forKey: "config.engineMode")
        let store = AppGroupStore(defaults: defaults)
        let llm = TimedStubLLMClient(
            polished: config.polishedTranscript,
            delayNanoseconds: config.polishDelayNanoseconds
        )
        let polishStart = ContinuousClock.now
        let polishService = PolishingService(store: store, client: llm)
        let polishOutcome = try await polishService.polishWithOutcome(
            guarded,
            context: PolishContext()
        )
        timings.polishSeconds = elapsedSeconds(since: polishStart)
        timings.polishedText = polishOutcome.text

        // --- bridge_deliver ---
        let bridgeStart = ContinuousClock.now
        let sessionId = UUID()
        let utteranceId = UUID()
        let result = FlowResult(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            status: .final,
            text: polishOutcome.text
        )
        FlowSessionBridge.writeResult(result, defaults: defaults)
        let latest = FlowSessionBridge.latestResult(defaults: defaults)
        let matched = FlowKeyboardResultMatcher.matchingResult(
            latest: latest,
            activeSessionId: sessionId,
            currentUtteranceId: utteranceId
        )
        timings.bridgeDeliverSeconds = elapsedSeconds(since: bridgeStart)
        timings.deliveredText = matched?.text ?? ""

        timings.totalSeconds = elapsedSeconds(since: totalStart)
        return timings
    }

    private static func elapsedSeconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }
}
