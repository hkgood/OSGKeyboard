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
    /// Optional short blurb shown under the provider name in the picker.
    public let blurb: String?

    public init(
        id: String,
        name: String,
        defaultBaseURL: String,
        defaultModel: String,
        apiKeyURL: URL? = nil,
        blurb: String? = nil
    ) {
        self.id = id
        self.name = name
        self.defaultBaseURL = defaultBaseURL
        self.defaultModel = defaultModel
        self.apiKeyURL = apiKeyURL
        self.blurb = blurb
    }

    public static let presets: [LLMProvider] = [
        .init(
            id: "openai",
            name: "OpenAI",
            defaultBaseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            apiKeyURL: URL(string: "https://platform.openai.com/api-keys"),
            blurb: "GPT-4o mini · 多语言"
        ),
        .init(
            id: "deepseek",
            name: "DeepSeek",
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-chat",
            apiKeyURL: URL(string: "https://platform.deepseek.com/api_keys"),
            blurb: "deepseek-chat · 中文友好"
        ),
        .init(
            id: "qwen",
            name: "Qwen (DashScope)",
            defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            defaultModel: "qwen-plus",
            apiKeyURL: URL(string: "https://dashscope.console.aliyun.com/apiKey"),
            blurb: "通义千问 · OpenAI 兼容"
        ),
        .init(
            id: "zhipu",
            name: "智谱 GLM",
            defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
            defaultModel: "glm-4-flash",
            apiKeyURL: URL(string: "https://bigmodel.cn/usercenter/apikeys"),
            blurb: "GLM-4-Flash · 中文优化"
        ),
        .init(
            id: "moonshot",
            name: "月之暗面 Moonshot",
            defaultBaseURL: "https://api.moonshot.cn/v1",
            defaultModel: "moonshot-v1-8k",
            apiKeyURL: URL(string: "https://platform.moonshot.cn/console/api-keys"),
            blurb: "Kimi · 长上下文"
        ),
        .init(
            id: "custom",
            name: "Custom (OpenAI-compatible)",
            defaultBaseURL: "",
            defaultModel: "",
            blurb: "自建 / 任意 OpenAI 兼容端点"
        )
    ]

    public static func provider(id: String) -> LLMProvider {
        presets.first(where: { $0.id == id }) ?? .presets[0]
    }
}
