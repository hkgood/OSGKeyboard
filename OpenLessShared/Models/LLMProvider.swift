// LLMProvider.swift
// OSGKeyboard · Shared
//
// Provider preset: a known cloud LLM with sensible defaults.
// User picks one of these on first launch, or defines a Custom one.

import Foundation

public struct LLMProvider: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let defaultBaseURL: String
    public let defaultModel: String
    public let apiKeyURL: URL?

    public init(
        id: String,
        name: String,
        defaultBaseURL: String,
        defaultModel: String,
        apiKeyURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.defaultBaseURL = defaultBaseURL
        self.defaultModel = defaultModel
        self.apiKeyURL = apiKeyURL
    }

    public static let presets: [LLMProvider] = [
        .init(
            id: "openai",
            name: "OpenAI",
            defaultBaseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            apiKeyURL: URL(string: "https://platform.openai.com/api-keys")
        ),
        .init(
            id: "deepseek",
            name: "DeepSeek",
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            apiKeyURL: URL(string: "https://platform.deepseek.com/api_keys")
        ),
        .init(
            id: "qwen",
            name: "Qwen (DashScope, OpenAI-compatible)",
            defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            defaultModel: "qwen-plus",
            apiKeyURL: URL(string: "https://dashscope.console.aliyun.com/apiKey")
        ),
        .init(
            id: "custom",
            name: "Custom (OpenAI-compatible)",
            defaultBaseURL: "",
            defaultModel: ""
        )
    ]

    public static func provider(id: String) -> LLMProvider {
        presets.first(where: { $0.id == id }) ?? .presets[0]
    }
}
