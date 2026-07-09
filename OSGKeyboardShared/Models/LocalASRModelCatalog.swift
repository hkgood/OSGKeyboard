// LocalASRModelCatalog.swift
// OSGKeyboard · Shared
//
// Bundled catalog of downloadable / manual local ASR models and Sherpa runtimes.

import Foundation

public enum LocalASRModelBackend: String, Codable, Sendable, Equatable {
    case mlx
    case sherpaQwen3
    case sherpaSenseVoice
    case appleSpeech
}

public enum LocalASRInstallKind: String, Codable, Sendable, Equatable {
    case manual
    case archive
    case runtime
}

public struct LocalASRDownloadSource: Codable, Sendable, Equatable {
    public let type: String
    public let priority: Int
    public let url: String
}

public struct LocalASRModelLayout: Codable, Sendable, Equatable {
    public var convFrontend: String?
    public var encoder: String?
    public var decoder: String?
    public var tokenizer: String?
    public var senseVoiceModel: String?
    public var tokens: String?
}

public struct LocalASRRuntimeDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let installRelativePath: String
    public let binaryCandidates: [String]
    public let archiveFileName: String
    public let sizeBytes: Int
    public let platform: String
    public let sources: [LocalASRDownloadSource]
}

public struct LocalASRModelDefinition: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let backend: LocalASRModelBackend
    public let sizeBytes: Int
    public let recommendedLocales: [String]
    public let supportsHotwords: Bool
    public let hotwordMode: LocalASRHotwordMode
    public let installKind: LocalASRInstallKind
    public let installRelativePath: String?
    public let archiveBaseName: String?
    public let layout: LocalASRModelLayout?
    public let requiredRelativeFiles: [String]?
    public let runtimePlatform: String?
    public let sources: [LocalASRDownloadSource]?
}

public struct LocalASRCatalogDocument: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let defaultModelId: String
    public let runtimes: [LocalASRRuntimeDefinition]
    public let models: [LocalASRModelDefinition]
}

public enum LocalASRModelCatalog {

    public static func loadBundled() throws -> LocalASRCatalogDocument {
        let bundle = Bundle(for: LocalASRCatalogBundleToken.self)
        guard let url = bundle.url(forResource: "local-asr-catalog", withExtension: "json") else {
            throw LocalASRModelCatalogError.missingBundledCatalog
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LocalASRCatalogDocument.self, from: data)
    }

    public static func model(_ id: String, in catalog: LocalASRCatalogDocument) -> LocalASRModelDefinition? {
        catalog.models.first { $0.id == id }
    }

    public static func capabilities(for model: LocalASRModelDefinition) -> LocalASRCapabilities {
        switch model.backend {
        case .mlx:
            return .qwen3MLX
        case .sherpaQwen3:
            return .sherpaQwen3
        case .sherpaSenseVoice:
            return .sherpaSenseVoice
        case .appleSpeech:
            return .appleSpeech
        }
    }

    #if os(macOS)
    public static func runtime(for platform: String, in catalog: LocalASRCatalogDocument) -> LocalASRRuntimeDefinition? {
        if platform == "macos-arm64" {
            return catalog.runtimes.first { $0.platform == "macos-arm64" }
        }
        if platform == "macos-x64" {
            return catalog.runtimes.first { $0.platform == "macos-x64" }
        }
        return catalog.runtimes.first
    }

    public static func currentRuntimePlatform() -> String {
        #if arch(arm64)
        return "macos-arm64"
        #else
        return "macos-x64"
        #endif
    }
    #endif
}

public enum LocalASRModelCatalogError: Error, LocalizedError {
    case missingBundledCatalog
    case modelNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .missingBundledCatalog:
            return "Missing bundled local ASR catalog."
        case .modelNotFound(let id):
            return "Local ASR model not found: \(id)"
        }
    }
}

private final class LocalASRCatalogBundleToken {}
