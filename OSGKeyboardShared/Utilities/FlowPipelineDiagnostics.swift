// FlowPipelineDiagnostics.swift
// OSGKeyboard · Shared
//
// Structured Flow pipeline metrics for Console.app filtering.

import Foundation
import os

public enum FlowPipelineDiagnostics {
    public static func logDrain(_ report: FlowCaptureDrainReport) {
        OSGLog.flow.info(
            "tailDrain duration=\(report.drainDurationSeconds, format: .fixed(precision: 2))s postRoll=\(report.postRollDurationSeconds, format: .fixed(precision: 2))s silenceEnd=\(report.endedBySilence) tailSamples=\(report.tailSampleCount)"
        )
    }

    public static func logTranscriptGuardUsedPartial(finalLength: Int, partialLength: Int) {
        OSGLog.flow.warning(
            "transcriptGuard partial preferred finalLen=\(finalLength) partialLen=\(partialLength)"
        )
    }

    public static func logFinalChunkRecovery(action: String, chunkIndex: Int) {
        OSGLog.asr.info("finalChunkRecovery \(action) chunk=\(chunkIndex)")
    }

    public static func logBatchFallback(
        sampleCount: Int,
        stitchedLength: Int,
        partialLength: Int,
        batchLength: Int
    ) {
        OSGLog.flow.info(
            "batchFallback samples=\(sampleCount) stitchedLen=\(stitchedLength) partialLen=\(partialLength) batchLen=\(batchLength)"
        )
    }

    public static func logChunkFinalize(
        chunkCount: Int,
        lastChunkSamples: Int,
        stitchedLength: Int,
        chunkWarnings: Int
    ) {
        OSGLog.flow.info(
            "chunkPipeline chunks=\(chunkCount) lastChunkSamples=\(lastChunkSamples) stitchedLen=\(stitchedLength) warnings=\(chunkWarnings)"
        )
    }

    public static func logStitcherSafeFallback(naiveLength: Int, mergedLength: Int) {
        OSGLog.asr.warning(
            "stitcher safe fallback naive=\(naiveLength) merged=\(mergedLength)"
        )
    }
}
