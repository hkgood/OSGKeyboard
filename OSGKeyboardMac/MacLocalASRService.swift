// MacLocalASRService.swift
// OSGKeyboard · Mac
//
// On-device ASR for macOS. Routes through the bundled local ASR catalog:
// Qwen3 MLX streaming (default), Apple Speech fallback.

import Foundation

enum MacLocalASRBackend: String, Sendable, CaseIterable {
    case mlxQwen3
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
    static let downloadSourceKey = LocalASRPreferenceKeys.downloadSource

    /// Preferred model download mirror; `.auto` picks by region (hf-mirror-friendly).
    static var downloadSource: LocalASRDownloadSourcePreference {
        get {
            guard let raw = UserDefaults.standard.string(forKey: downloadSourceKey),
                  let value = LocalASRDownloadSourcePreference(rawValue: raw) else {
                return .auto
            }
            return value
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: downloadSourceKey) }
    }

    static var selectedModelId: String {
        get {
            if let raw = UserDefaults.standard.string(forKey: selectedModelIdKey), !raw.isEmpty {
                return migratedModelId(raw)
            }
            return legacyBackend == .appleSpeech ? "apple-speech-fallback" : "qwen3-mlx-0.6b-4bit"
        }
        set { UserDefaults.standard.set(newValue, forKey: selectedModelIdKey) }
    }

    /// Maps removed Sherpa / legacy catalog entries to the current MLX default.
    static func migratedModelId(_ id: String) -> String {
        switch id {
        case "sherpa-qwen3-0.6b-int8",
             "sherpa-qwen3-1.7b-int8",
             "sherpa-sensevoice-small-int8",
             "sherpa-paraformer-zh-int8",
             "qwen3-mlx-1.7b":
            return "qwen3-mlx-0.6b-4bit"
        default:
            return id
        }
    }

    static var legacyBackend: MacLocalASRBackend {
        guard let raw = UserDefaults.standard.string(forKey: backendKey) else {
            return .mlxQwen3
        }
        if raw == "qwen3MLX" || raw == "sherpaQwen3" || raw == "mlxQwen3" {
            return .mlxQwen3
        }
        if raw == "appleSpeech" { return .appleSpeech }
        return .mlxQwen3
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

    /// Whether the active local engine uses MLX streaming for live partials.
    static func usesMLXLiveStreaming() -> Bool {
        guard let model = selectedModelDefinition() else { return false }
        return model.backend == .mlx && isModelInstalled(model)
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

        return try await MacSpeechLocalASR.transcribe(samples: samples, locale: locale, bias: bias)
    }

    private static func transcribeWithModel(
        _ model: LocalASRModelDefinition,
        samples: [Float],
        locale: Locale,
        bias: LocalASRBiasPayload?
    ) async throws -> String {
        switch model.backend {
        case .mlx:
            return try await MacMLXStreamingASRProvider.shared.transcribeBatch(
                samples: samples,
                model: model,
                locale: locale,
                bias: bias
            )
        case .appleSpeech:
            return try await MacSpeechLocalASR.transcribe(samples: samples, locale: locale, bias: bias)
        case .sherpaQwen3, .sherpaSenseVoice, .sherpaParaformer:
            throw MacLocalASRError.qwen3ModelMissing
        }
    }
}
