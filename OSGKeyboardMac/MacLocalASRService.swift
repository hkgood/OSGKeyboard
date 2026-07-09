// MacLocalASRService.swift
// OSGKeyboard · Mac
//
// On-device ASR for macOS. Routes through the bundled local ASR catalog:
// Sherpa Qwen3 (default), Paraformer, SenseVoice, Apple Speech fallback.

import Foundation

enum MacLocalASRBackend: String, Sendable, CaseIterable {
    case sherpaQwen3
    case sherpaParaformer
    case sherpaSenseVoice
    case appleSpeech
}

enum MacLocalASRError: Error, LocalizedError {
    case qwen3ModelMissing
    case qwen3LoadFailed(String)
    case qwen3InferenceFailed(String)
    case speechDenied
    case speechFailed(String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .qwen3ModelMissing:
            return MacL10n.string("mac.error.qwen3ModelMissing")
        case .qwen3LoadFailed(let detail):
            return MacL10n.format("mac.error.qwen3LoadFailed", detail)
        case .qwen3InferenceFailed(let detail):
            return MacL10n.format("mac.error.qwen3InferenceFailed", detail)
        case .speechDenied:
            return "Speech recognition permission denied"
        case .speechFailed(let detail):
            return detail
        case .emptyTranscript:
            return MacL10n.string("mac.error.emptyTranscript")
        }
    }
}

enum MacLocalASRPreferences {
    static let backendKey = "mac.localASR.backend"
    static let selectedModelIdKey = LocalASRPreferenceKeys.selectedModelId
    /// Legacy MLX path key — retained for migration only.
    static let qwen3ModelRelativePath = "models/qwen3-asr-1.7b-mlx"

    static var selectedModelId: String {
        get {
            if let raw = UserDefaults.standard.string(forKey: selectedModelIdKey), !raw.isEmpty {
                return migratedModelId(raw)
            }
            return legacyBackend == .appleSpeech ? "apple-speech-fallback" : "sherpa-qwen3-0.6b-int8"
        }
        set { UserDefaults.standard.set(newValue, forKey: selectedModelIdKey) }
    }

    /// Maps removed catalog entries to the current default Sherpa model.
    static func migratedModelId(_ id: String) -> String {
        switch id {
        case "qwen3-mlx-1.7b":
            return "sherpa-qwen3-0.6b-int8"
        default:
            return id
        }
    }

    static var legacyBackend: MacLocalASRBackend {
        guard let raw = UserDefaults.standard.string(forKey: backendKey),
              let value = MacLocalASRBackend(rawValue: raw) else {
            return .sherpaQwen3
        }
        if raw == "qwen3MLX" { return .sherpaQwen3 }
        return value
    }
}

enum MacLocalASRService {

    static func loadCatalog() -> LocalASRCatalogDocument? {
        try? LocalASRModelCatalog.loadBundled()
    }

    static func selectedModelDefinition() -> LocalASRModelDefinition? {
        guard let catalog = loadCatalog() else { return nil }
        let manifest = LocalASRInstalledManifestIO.load(defaultModelId: catalog.defaultModelId)
        let selectedId = manifest.selectedModelId.isEmpty
            ? MacLocalASRPreferences.selectedModelId
            : MacLocalASRPreferences.migratedModelId(manifest.selectedModelId)
        if selectedId == "apple-speech-fallback" { return nil }
        return LocalASRModelCatalog.model(selectedId, in: catalog)
            ?? LocalASRModelCatalog.model(catalog.defaultModelId, in: catalog)
    }

    static func currentCapabilities() -> LocalASRCapabilities {
        guard let model = selectedModelDefinition() else { return .appleSpeech }
        return LocalASRModelCatalog.capabilities(for: model)
    }

    static func currentBackendLabel() -> String {
        guard let model = selectedModelDefinition() else { return "Apple Speech" }
        return model.displayName
    }

    static func isModelInstalled(_ model: LocalASRModelDefinition) -> Bool {
        LocalASRModelInstallState.isInstalled(
            model,
            manualMLXPath: nil,
            fileManager: FileManager.default
        )
    }

    /// Transcribe using the selected catalog model, falling back to Apple Speech.
    static func transcribe(
        samples: [Float],
        locale: Locale,
        bias: LocalASRBiasPayload? = nil
    ) async throws -> String {
        if let model = selectedModelDefinition(), isModelInstalled(model) {
            return try await transcribeWithModel(model, samples: samples, locale: locale, bias: bias)
        }

        return try await MacSpeechLocalASR.transcribe(samples: samples, locale: locale)
    }

    private static func transcribeWithModel(
        _ model: LocalASRModelDefinition,
        samples: [Float],
        locale: Locale,
        bias: LocalASRBiasPayload?
    ) async throws -> String {
        switch model.backend {
        case .mlx:
            throw MacLocalASRError.qwen3ModelMissing
        case .sherpaQwen3, .sherpaSenseVoice, .sherpaParaformer:
            return try await MacSherpaLocalASR.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                model: model,
                bias: bias
            )
        case .appleSpeech:
            return try await MacSpeechLocalASR.transcribe(samples: samples, locale: locale)
        }
    }
}
