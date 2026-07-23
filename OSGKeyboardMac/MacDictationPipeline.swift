// MacDictationPipeline.swift
// OSGKeyboard · Mac
//
// Dictation pipeline: samples → ASR (cloud or local MLX streaming) → polish.

import Foundation

enum MacDictationError: Error, LocalizedError {
    case noAudio
    case providerHasNoCloudASR
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .noAudio:
            return MacL10n.string("mac.error.noAudio")
        case .providerHasNoCloudASR:
            return MacL10n.string("mac.error.noCloudASR")
        case .emptyTranscript:
            return MacL10n.string("mac.error.emptyTranscript")
        }
    }
}

/// Outcome of ASR that ran while the microphone was still open.
struct MacLiveASRCaptureResult: Sendable {
    let raw: String
    let chunkWarning: String?
    let localBias: LocalASRBiasPayload?
    /// When true, callers should fall back to batch ASR on the recorded samples.
    let shouldFallbackToBatch: Bool
}

enum MacDictationPipeline {
    /// Whether the active engine can surface `onPartial` text while recording.
    static func supportsLivePartials(store: AppGroupStore) -> Bool {
        if store.engineMode == "local" {
            return MacLocalASRService.usesMLXLiveStreaming()
        }
        let strategy = CloudASRModelCatalog.strategy(for: store.asrProviderId)
        return strategy != .localFallback
    }

    /// Runs ASR then polish. Polish failures return cleaned raw ASR plus a warning.
    static func run(
        samples: [Float],
        store: AppGroupStore,
        onPartial: (@Sendable (String) -> Void)? = nil
    ) async throws -> MacDictationResult {
        guard !samples.isEmpty else { throw MacDictationError.noAudio }

        let locale = resolvedLocale(store: store)
        let raw: String
        var localBias: LocalASRBiasPayload?

        if store.engineMode == "local" {
            localBias = resolveLocalBias(store: store, locale: locale)
            raw = try await MacLocalASRService.transcribe(
                samples: samples,
                locale: locale,
                bias: localBias
            )
            onPartial?(raw)
        } else {
            let strategy = CloudASRModelCatalog.strategy(for: store.asrProviderId)
            guard strategy != .localFallback else { throw MacDictationError.providerHasNoCloudASR }

            let client = CloudASRClientFactory.make(store: store)
            try? await client.prepare(dictionary: store.personalDictionary)
            raw = try await client.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                dictionary: store.personalDictionary
            )
        }

        return try await polishCapturedASR(
            raw: raw,
            store: store,
            localBias: localBias,
            chunkWarning: nil
        )
    }

    /// Consumes a live mic snapshot stream until finished; yields stitched partials.
    static func captureLive(
        stream: AsyncStream<AudioBufferSnapshot>,
        finishSignal: AsyncStream<Void>,
        store: AppGroupStore,
        onPartial: @escaping @Sendable (String) -> Void
    ) async -> MacLiveASRCaptureResult {
        if store.engineMode == "local", MacLocalASRService.usesMLXLiveStreaming() {
            return await MacMLXLiveCapture.run(
                audioStream: stream,
                finishSignal: finishSignal,
                store: store,
                onPartial: onPartial
            )
        }

        let locale = resolvedLocale(store: store)
        let localBias: LocalASRBiasPayload?
        if store.engineMode == "local" {
            localBias = resolveLocalBias(store: store, locale: locale)
        } else {
            localBias = nil
        }

        do {
            let adapter = try makeChunkASRAdapter(store: store)
            if let cloudAdapter = adapter as? MacCloudASRChunkAdapter {
                try? await cloudAdapter.prepare()
            }

            let pipeline = ChunkedUtterancePipeline(
                asr: adapter,
                locale: locale,
                config: .flowDefault
            )
            let outcome = await pipeline.transcribe(stream: stream, onPartial: onPartial)

            switch outcome {
            case .success(let success):
                return MacLiveASRCaptureResult(
                    raw: success.text,
                    chunkWarning: success.chunkWarnings.first,
                    localBias: localBias,
                    shouldFallbackToBatch: false
                )
            case .failure:
                return MacLiveASRCaptureResult(
                    raw: "",
                    chunkWarning: nil,
                    localBias: localBias,
                    shouldFallbackToBatch: true
                )
            case .cancelled:
                return MacLiveASRCaptureResult(
                    raw: "",
                    chunkWarning: nil,
                    localBias: localBias,
                    shouldFallbackToBatch: true
                )
            }
        } catch {
            return MacLiveASRCaptureResult(
                raw: "",
                chunkWarning: nil,
                localBias: localBias,
                shouldFallbackToBatch: true
            )
        }
    }

    /// Polish-only step after live or batch ASR has produced raw text.
    static func polishCapturedASR(
        raw: String,
        store: AppGroupStore,
        localBias: LocalASRBiasPayload?,
        chunkWarning: String?
    ) async throws -> MacDictationResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MacDictationError.emptyTranscript }

        let postASR: String
        if let localBias, !localBias.correctionPairs.isEmpty {
            postASR = LocalASRTranscriptCorrector.apply(trimmed, pairs: localBias.correctionPairs)
        } else {
            postASR = trimmed
        }

        let polishContext: PolishContext?
        if let supplement = localBias?.polishFragment.trimmingCharacters(in: .whitespacesAndNewlines),
           !supplement.isEmpty {
            polishContext = PolishContext(
                appContext: store.detectedAppContext?.context ?? .unknown,
                intensity: store.polishIntensity,
                dictionarySupplement: supplement
            )
        } else {
            polishContext = nil
        }

        do {
            let polished = try await PolishingService(store: store).polish(
                postASR,
                mode: store.polishModeForPipeline,
                context: polishContext
            )
            guard !polished.isEmpty else {
                throw PolishingService.PolishError.noTranscript
            }
            return MacDictationResult(
                text: polished,
                polishWarning: nil,
                chunkWarning: chunkWarning
            )
        } catch {
            let delivery = TranscriptionPolishFallback.makeDelivery(
                rawText: postASR,
                error: error,
                engineMode: store.engineMode,
                chunkWarning: chunkWarning
            )
            return MacDictationResult(
                text: delivery.text,
                polishWarning: delivery.polishWarning,
                chunkWarning: nil
            )
        }
    }

    // MARK: - Private

    private static func resolvedLocale(store: AppGroupStore) -> Locale {
        Locale(identifier: store.localeId.isEmpty ? "zh-CN" : store.localeId)
    }

    private static func resolveLocalBias(
        store: AppGroupStore,
        locale: Locale
    ) -> LocalASRBiasPayload? {
        MacAppContextService.captureAndPersist(to: store)
        let capabilities = MacLocalASRService.currentCapabilities()
        let bias = LocalASRBiasAdapter.adapt(
            LocalASRBiasRequest(
                dictionary: store.personalDictionary,
                locale: locale,
                frontAppBundleId: MacAppContextService.frontmostBundleIdentifier(),
                capabilities: capabilities
            )
        )
        LocalASRBiasDiagnosticsStore.save(
            payload: bias,
            modelId: MacLocalASRService.selectedModelDefinition()?.id,
            backendLabel: MacLocalASRService.currentBackendLabel()
        )
        return bias
    }

    private static func makeChunkASRAdapter(store: AppGroupStore) throws -> any ASRChunkTranscribing {
        try MacCloudASRChunkAdapter(store: store)
    }
}
