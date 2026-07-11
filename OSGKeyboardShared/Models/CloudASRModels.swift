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
    /// 百炼 Fun-ASR Realtime — DashScope 经典 inference WebSocket 流式。
    case bailianStreaming
    /// OpenAI / Groq / 硅基流动 / Whisper 等 — `prompt` on transcription APIs.
    case prompt
    /// OpenRouter `/audio/transcriptions` — JSON body + base64 WAV (not multipart).
    case openRouterJson
    /// 火山引擎 SAUC 大模型流式 ASR（WebSocket + binary frame）。
    case volcengineStreaming
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
    /// Provider ids shown in the cloud ASR picker (explicit allowlist).
    public static let selectableProviderIds: Set<String> = [
        "openai",
        "whisper",
        "bailian",
        "zhipu",
        "groq",
        "siliconflow",
        "openrouter",
        "mimo",
        "volcengine",
        "custom",
    ]

    /// Sync Fun-ASR Flash — base64 upload, ≤ 5 min, supports context + vocabulary.
    public static let alibabaFunASRFlash = "fun-asr-flash-2026-06-15"
    public static let alibabaFunASRRealtime = "fun-asr-realtime"
    /// Must match the ASR model used at recognition time.
    public static let alibabaVocabularyTargetModel = alibabaFunASRFlash

    public static let zhipuGLMASR = "glm-asr-2512"
    public static let openAITranscribe = "gpt-4o-mini-transcribe"
    public static let openAIWhisper = "whisper-1"
    public static let mimoASR = "mimo-v2.5-asr"
    public static let groqWhisper = "whisper-large-v3-turbo"
    public static let siliconflowASR = "FunAudioLLM/SenseVoiceSmall"
    public static let openrouterWhisper = "openai/whisper-large-v3-turbo"
    public static let volcengineDefaultResourceID = "volc.seedasr.sauc.duration"
    public static let volcengineEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    public static let bailianDefaultEndpoint = "wss://dashscope.aliyuncs.com/api-ws/v1/inference/"

    public static let alibabaAPIBase = "https://dashscope.aliyuncs.com/api/v1"
    public static let alibabaCustomizationPath = "/services/audio/asr/customization"
    public static let alibabaMultimodalPath = "/services/aigc/multimodal-generation/generation"
    public static let zhipuTranscriptionPath = "/audio/transcriptions"

    public static func supportsCloudASRSelection(providerId: String) -> Bool {
        selectableProviderIds.contains(providerId)
    }

    public static func strategy(for providerId: String) -> CloudASRStrategy {
        switch providerId {
        case "zhipu":
            return .zhipuHotwords
        case "bailian":
            return .bailianStreaming
        case "moonshot":
            return .localFallback
        case "volcengine":
            return .volcengineStreaming
        case "openrouter":
            return .openRouterJson
        case "openai", "whisper", "mimo", "groq", "siliconflow", "custom":
            return .prompt
        default:
            return .localFallback
        }
    }

    public static func defaultModel(for providerId: String) -> String {
        switch providerId {
        case "zhipu":
            return zhipuGLMASR
        case "bailian":
            return alibabaFunASRRealtime
        case "whisper":
            return openAIWhisper
        case "mimo":
            return mimoASR
        case "groq":
            return groqWhisper
        case "siliconflow":
            return siliconflowASR
        case "openrouter":
            return openrouterWhisper
        case "volcengine":
            return volcengineDefaultResourceID
        case "openai", "custom":
            return openAITranscribe
        default:
            return openAITranscribe
        }
    }

    /// Whether the ASR settings card should expose a custom endpoint field.
    public static func showsASREndpointField(for providerId: String) -> Bool {
        switch strategy(for: providerId) {
        case .prompt, .openRouterJson, .bailianStreaming:
            return true
        case .zhipuHotwords, .volcengineStreaming, .localFallback:
            return false
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
        case .zhipuHotwords:
            return true
        case .bailianStreaming, .prompt, .openRouterJson, .volcengineStreaming, .localFallback:
            return false
        }
    }
}
