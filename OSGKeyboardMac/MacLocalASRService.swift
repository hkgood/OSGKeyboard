// MacLocalASRService.swift
// OSGKeyboard · Mac
//
// On-device ASR for macOS. Routes through the bundled local ASR catalog:
// Qwen3 MLX (default), Sherpa Qwen3 hotwords POC, SenseVoice, Apple Speech fallback.

import Foundation

enum MacLocalASRBackend: String, Sendable, CaseIterable {
    case qwen3MLX
    case sherpaQwen3
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
    /// Shared managed subfolder for the manually-provided MLX weights.
    static let qwen3ModelRelativePath = "models/qwen3-asr-1.7b-mlx"

    static var selectedModelId: String {
        get {
            if let raw = UserDefaults.standard.string(forKey: selectedModelIdKey), !raw.isEmpty {
                return raw
            }
            return legacyBackend == .appleSpeech ? "apple-speech-fallback" : "qwen3-mlx-1.7b"
        }
        set { UserDefaults.standard.set(newValue, forKey: selectedModelIdKey) }
    }

    static var legacyBackend: MacLocalASRBackend {
        guard let raw = UserDefaults.standard.string(forKey: backendKey),
              let value = MacLocalASRBackend(rawValue: raw) else {
            return .qwen3MLX
        }
        return value
    }

    /// Fixed location inside the shared managed model storage root. All three
    /// catalog models live under the same directory, so MLX no longer needs a
    /// per-model folder picker — the user drops converted weights here.
    static var qwen3ModelPath: String {
        LocalASRModelInstallState.installDirectory(for: qwen3ModelRelativePath).path
    }

    static func qwen3ModelIsInstalled(at path: String = qwen3ModelPath) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        let fm = FileManager.default
        let config = (path as NSString).appendingPathComponent("config.json")
        let weights = (path as NSString).appendingPathComponent("model.safetensors")
        guard fm.fileExists(atPath: config), fm.fileExists(atPath: weights) else {
            return false
        }
        let names = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        return names.contains("vocab.json") && names.contains("merges.txt")
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
            : manifest.selectedModelId
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
            manualMLXPath: MacLocalASRPreferences.qwen3ModelPath
        )
    }

    /// Transcribe using the selected catalog model, with MLX → Apple Speech fallback.
    static func transcribe(
        samples: [Float],
        locale: Locale,
        bias: LocalASRBiasPayload? = nil
    ) async throws -> String {
        if let model = selectedModelDefinition(), isModelInstalled(model) {
            do {
                return try await transcribeWithModel(model, samples: samples, locale: locale, bias: bias)
            } catch {
                if model.backend != .mlx {
                    throw error
                }
            }
        }

        if MacLocalASRPreferences.qwen3ModelIsInstalled() {
            return try await MacQwen3LocalASR.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                modelPath: MacLocalASRPreferences.qwen3ModelPath,
                bias: bias
            )
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
            return try await MacQwen3LocalASR.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: locale,
                modelPath: MacLocalASRPreferences.qwen3ModelPath,
                bias: bias
            )
        case .sherpaQwen3, .sherpaSenseVoice:
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
