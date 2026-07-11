// LocalASRModelCatalog.swift
// OSGKeyboard · Shared
//
// Bundled catalog of downloadable / manual local ASR models and Sherpa runtimes.

import Foundation

public enum LocalASRModelBackend: String, Codable, Sendable, Equatable {
    case mlx
    case sherpaQwen3
    case sherpaSenseVoice
    case sherpaParaformer
    case appleSpeech
}

public enum LocalASRInstallKind: String, Codable, Sendable, Equatable {
    case manual
    case archive
    /// Multi-file install from a remote repository (ModelScope / HuggingFace file API).
    case repository
    case runtime
}

public struct LocalASRDownloadFile: Codable, Sendable, Equatable {
    public let remotePath: String
    public let localPath: String
    public let sizeBytes: Int?
}

public struct LocalASRDownloadSource: Codable, Sendable, Equatable {
    public let type: String
    public let priority: Int
    /// Full URL for a single archive download.
    public let url: String
    /// Base URL template for repository installs; must contain `{path}`.
    public let baseURL: String?
    public let files: [LocalASRDownloadFile]?

    public var isRepository: Bool {
        guard let files, !files.isEmpty else { return false }
        return baseURL?.contains("{path}") == true
    }

    public var isArchive: Bool {
        !url.isEmpty && !isRepository
    }
}

public struct LocalASRModelLayout: Codable, Sendable, Equatable {
    public var convFrontend: String?
    public var encoder: String?
    public var decoder: String?
    public var tokenizer: String?
    public var senseVoiceModel: String?
    public var paraformerModel: String?
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
    /// Optional localization key for a short quality/speed badge
    /// (e.g. `mac.localASR.badge.fastest`).
    public let badgeKey: String?
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
        case .sherpaParaformer:
            return .sherpaParaformer
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

/// Region-aware ordering for local ASR model download mirrors.
public enum LocalASRDownloadSourceSorter {

    /// `true` when the system region is mainland China (`CN`).
    public static func isChinaMainland(region: Locale.Region? = Locale.current.region) -> Bool {
        region?.identifier == "CN"
    }

    /// Lower rank = tried earlier. CN: ModelScope → HuggingFace → GitHub; elsewhere: HF → GitHub → ModelScope.
    public static func typeRank(_ type: String, chinaFirst: Bool) -> Int {
        switch type.lowercased() {
        case "modelscope":
            return chinaFirst ? 0 : 2
        case "huggingface":
            return chinaFirst ? 1 : 0
        case "github":
            return 1
        default:
            return 3
        }
    }

    public static func sorted(
        _ sources: [LocalASRDownloadSource],
        region: Locale.Region? = Locale.current.region
    ) -> [LocalASRDownloadSource] {
        let chinaFirst = isChinaMainland(region: region)
        return sources.sorted { lhs, rhs in
            let leftRank = typeRank(lhs.type, chinaFirst: chinaFirst)
            let rightRank = typeRank(rhs.type, chinaFirst: chinaFirst)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.priority < rhs.priority
        }
    }
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
