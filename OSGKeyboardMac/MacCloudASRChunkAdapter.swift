// MacCloudASRChunkAdapter.swift
// OSGKeyboard · Mac
//
// Adapts configured cloud ASR clients to the shared chunked utterance pipeline.

import Foundation
import os

final class MacCloudASRChunkAdapter: ASRChunkTranscribing, @unchecked Sendable {
    private let store: AppGroupStore
    private let client: CloudASRTranscribing
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    init(store: AppGroupStore) throws {
        let strategy = CloudASRModelCatalog.strategy(for: store.asrProviderId)
        guard strategy != .localFallback else {
            throw MacDictationError.providerHasNoCloudASR
        }
        self.store = store
        self.client = CloudASRClientFactory.make(store: store)
    }

    func prepare() async throws {
        try await client.prepare(dictionary: store.personalDictionary)
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
            let text = try await client.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                dictionary: store.personalDictionary
            )
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(trimmed)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
