// MacSherpaLocalASR.swift
// OSGKeyboard · Mac
//
// Sherpa-onnx backed local ASR (Qwen3 hotwords POC + SenseVoice baseline).

import Foundation

enum MacSherpaLocalASR {

    static func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        model: LocalASRModelDefinition,
        bias: LocalASRBiasPayload?
    ) async throws -> String {
        let catalog = try LocalASRModelCatalog.loadBundled()
        let manager = LocalASRModelManager.shared
        guard let layout = model.layout,
              let modelRoot = LocalASRModelInstallState.modelRootURL(model) else {
            throw MacLocalASRError.qwen3ModelMissing
        }

        try await manager.ensureRuntimeInstalled(catalog: catalog)
        guard let runtime = LocalASRModelCatalog.runtime(
            for: LocalASRModelCatalog.currentRuntimePlatform(),
            in: catalog
        ),
        let binary = LocalASRModelInstallState.resolveRuntimeBinary(runtime: runtime) else {
            throw MacLocalASRError.qwen3LoadFailed("Sherpa runtime binary missing")
        }

        switch model.backend {
        case .sherpaQwen3:
            return try await MacSherpaONNXRunner.transcribeQwen3(
                samples: samples,
                sampleRate: sampleRate,
                locale: locale,
                modelRoot: modelRoot,
                layout: layout,
                runtimeBinary: binary,
                bias: bias
            )
        case .sherpaSenseVoice:
            return try await MacSherpaONNXRunner.transcribeSenseVoice(
                samples: samples,
                sampleRate: sampleRate,
                modelRoot: modelRoot,
                layout: layout,
                runtimeBinary: binary
            )
        case .sherpaParaformer:
            return try await MacSherpaONNXRunner.transcribeParaformer(
                samples: samples,
                sampleRate: sampleRate,
                modelRoot: modelRoot,
                layout: layout,
                runtimeBinary: binary
            )
        default:
            throw MacLocalASRError.qwen3InferenceFailed("Unsupported Sherpa backend")
        }
    }
}
