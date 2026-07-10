// MacLocalASRChunkAdapter.swift
// OSGKeyboard · Mac
//
// Adapts macOS local ASR to the shared chunked utterance pipeline.

import Foundation
import os

final class MacLocalASRChunkAdapter: ASRChunkTranscribing, @unchecked Sendable {
    private let locale: Locale
    private let bias: LocalASRBiasPayload?
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    init(locale: Locale, bias: LocalASRBiasPayload?) {
        self.locale = locale
        self.bias = bias
    }

    func resetForNewUtterance() {
        cancelled.withLock { $0 = false }
    }

    func cancel() {
        cancelled.withLock { $0 = true }
    }

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        let isCancelled = cancelled.withLock { $0 }
        if isCancelled || Task.isCancelled { return .cancelled }
        guard !samples.isEmpty else { return .success("") }

        do {
            let text = try await MacLocalASRService.transcribe(
                samples: samples,
                locale: locale,
                bias: bias
            )
            return .success(text)
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
