// LLMRequest.swift
// OSGKeyboard · Shared
//
// OpenAI-compatible chat completion request/response models.
// Compatible with OpenAI, DeepSeek, Qwen DashScope, and any provider that
// implements POST {baseURL}/chat/completions.

import Foundation

public struct LLMRequest: Codable, Sendable {
    public let model: String
    public let messages: [Message]
    public let temperature: Double?
    public let maxTokens: Int?
    public let topP: Double?

    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
    }

    public enum Message: Codable, Sendable {
        case system(String)
        case user(String)
        case assistant(String)

        private enum CodingKeys: String, CodingKey {
            case role, content
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .system(let s):
                try c.encode("system", forKey: .role); try c.encode(s, forKey: .content)
            case .user(let s):
                try c.encode("user", forKey: .role); try c.encode(s, forKey: .content)
            case .assistant(let s):
                try c.encode("assistant", forKey: .role); try c.encode(s, forKey: .content)
            }
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let role = try c.decode(String.self, forKey: .role)
            let content = try c.decode(String.self, forKey: .content)
            switch role {
            case "system": self = .system(content)
            case "user": self = .user(content)
            case "assistant": self = .assistant(content)
            default:
                throw DecodingError.dataCorruptedError(forKey: .role, in: c,
                    debugDescription: "Unknown role \(role)")
            }
        }
    }

    public init(
        model: String,
        messages: [Message],
        temperature: Double? = 0.1,
        maxTokens: Int? = nil,
        topP: Double? = 0.9
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    /// Coarse estimate used only for a safe output ceiling.
    public static func estimatedTokenCount(for text: String) -> Int {
        var cjkCount = 0
        var nonCJKCount = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                cjkCount += 1
            default:
                nonCJKCount += 1
            }
        }
        return max(1, cjkCount + Int(ceil(Double(nonCJKCount) / 4.0)))
    }

    public static func outputTokenLimit(for text: String) -> Int {
        min(4_096, max(256, estimatedTokenCount(for: text) * 2))
    }
}

public struct LLMResponse: Codable, Sendable {
    public let id: String?
    public let choices: [Choice]
    public let usage: Usage?

    public struct Usage: Codable, Sendable {
        public let promptTokens: Int?
        public let promptCacheHitTokens: Int?
        public let promptTokensDetails: PromptTokensDetails?

        public struct PromptTokensDetails: Codable, Sendable {
            public let cachedTokens: Int?

            private enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case promptCacheHitTokens = "prompt_cache_hit_tokens"
            case promptTokensDetails = "prompt_tokens_details"
        }

        public var cachedTokens: Int? {
            promptCacheHitTokens ?? promptTokensDetails?.cachedTokens
        }
    }

    public struct Choice: Codable, Sendable {
        public let index: Int
        public let message: LLMRequest.Message
        public let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    public var content: String {
        switch choices.first?.message {
        case .system(let s), .user(let s), .assistant(let s):
            return s
        case .none:
            return ""
        }
    }
}
