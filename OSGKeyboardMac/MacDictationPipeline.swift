// MacDictationPipeline.swift
// OSGKeyboard · Mac
//
// Dictation pipeline: samples → ASR (cloud or local) → polish.
// Cloud path reuses `CloudASRClientFactory`; local path uses Qwen3-ASR (MLX)
// with Apple Speech fallback when weights are missing.

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

enum MacDictationPipeline {
    /// Runs ASR then best-effort polish. Polish failures fall back to raw text.
    static func run(samples: [Float], store: AppGroupStore) async throws -> String {
        guard !samples.isEmpty else { throw MacDictationError.noAudio }

        let locale = Locale(identifier: store.localeId.isEmpty ? "zh-CN" : store.localeId)
        let raw: String
        var localBias: LocalASRBiasPayload?

        if store.engineMode == "local" {
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
            localBias = bias
            LocalASRBiasDiagnosticsStore.save(
                payload: bias,
                modelId: MacLocalASRService.selectedModelDefinition()?.id,
                backendLabel: MacLocalASRService.currentBackendLabel()
            )
            raw = try await MacLocalASRService.transcribe(
                samples: samples,
                locale: locale,
                bias: bias
            )
        } else {
            let strategy = CloudASRModelCatalog.strategy(for: store.providerId)
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

        if let polished = try? await PolishingService(store: store).polish(
            postASR,
            mode: store.polishModeForPipeline,
            context: polishContext
        ),
           !polished.isEmpty {
            return polished
        }
        return postASR
    }
}
