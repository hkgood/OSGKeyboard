// CloudASRModels.swift
// OSGKeyboard · Shared
//
// Cloud-engine ASR routing: which provider uses official hotwords /
// vocabulary APIs vs. a transcription prompt bias.

import Foundation

/// How a cloud provider applies the user's personal dictionary during ASR.
public enum CloudASRStrategy: String, Sendable, Equatable {
    /// 智谱 GLM-ASR — `hotwords` + optional `prompt`.
    case zhipuHotwords
    /// 阿里百炼 Fun-ASR — managed `vocabulary_id` + context text.
    case alibabaVocabulary
    /// OpenAI / 小米 MiMo / 自定义端点 — `prompt` on transcription APIs.
    case prompt
    /// Moonshot 托管 API 暂无音频转写；云端引擎回退端侧 ASR。
    case localFallback
}

public enum CloudASRError: Error, LocalizedError, Sendable, Equatable {
    case noAPIKey
    case invalidURL
    case http(status: Int, message: String?)
    case decoding(String)
    case transport(String)
    case emptyTranscript
    case audioTooLong
    case providerUnsupported

    public var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return SharedL10n.string("error.cloudASR.noAPIKey")
        case .invalidURL:
            return SharedL10n.string("error.cloudASR.invalidURL")
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return SharedL10n.format("error.cloudASR.httpWithMessage", status, message)
            }
            return SharedL10n.format("error.cloudASR.http", status)
        case .decoding(let detail):
            return SharedL10n.format("error.cloudASR.decoding", detail)
        case .transport(let detail):
            return SharedL10n.format("error.cloudASR.transport", detail)
        case .emptyTranscript:
            return SharedL10n.string("error.cloudASR.emptyTranscript")
        case .audioTooLong:
            return SharedL10n.string("error.cloudASR.audioTooLong")
        case .providerUnsupported:
            return SharedL10n.string("error.cloudASR.providerUnsupported")
        }
    }
}

public enum CloudASRModelCatalog {
    /// Sync Fun-ASR Flash — base64 upload, ≤ 5 min, supports context + vocabulary.
    public static let alibabaFunASRFlash = "fun-asr-flash-2026-06-15"
    /// Must match the ASR model used at recognition time.
    public static let alibabaVocabularyTargetModel = alibabaFunASRFlash

    public static let zhipuGLMASR = "glm-asr-2512"
    public static let openAITranscribe = "gpt-4o-mini-transcribe"
    public static let openAIWhisper = "whisper-1"
    public static let mimoASR = "mimo-v2.5-asr"

    public static let alibabaAPIBase = "https://dashscope.aliyuncs.com/api/v1"
    public static let alibabaCustomizationPath = "/services/audio/asr/customization"
    public static let alibabaMultimodalPath = "/services/aigc/multimodal-generation/generation"
    public static let zhipuTranscriptionPath = "/audio/transcriptions"

    public static func strategy(for providerId: String) -> CloudASRStrategy {
        switch providerId {
        case "zhipu":
            return .zhipuHotwords
        case "qwen":
            return .alibabaVocabulary
        case "moonshot":
            return .localFallback
        case "openai", "mimo", "custom":
            return .prompt
        default:
            return .prompt
        }
    }

    public static func defaultModel(for providerId: String) -> String {
        switch providerId {
        case "zhipu":
            return zhipuGLMASR
        case "qwen":
            return alibabaFunASRFlash
        case "mimo":
            return mimoASR
        case "openai", "custom":
            return openAITranscribe
        default:
            return openAITranscribe
        }
    }
}

extension LLMProvider {
    public var cloudASRStrategy: CloudASRStrategy {
        CloudASRModelCatalog.strategy(for: id)
    }

    public var defaultCloudASRModel: String {
        CloudASRModelCatalog.defaultModel(for: id)
    }

    /// Official hotwords / vocabulary APIs during cloud ASR (not prompt-only bias).
    public var supportsPersonalDictionaryCloudASR: Bool {
        switch cloudASRStrategy {
        case .zhipuHotwords, .alibabaVocabulary:
            return true
        case .prompt, .localFallback:
            return false
        }
    }
}
