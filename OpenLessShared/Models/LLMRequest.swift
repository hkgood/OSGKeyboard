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
        temperature: Double? = 0.3,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct LLMResponse: Codable, Sendable {
    public let id: String?
    public let choices: [Choice]

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
