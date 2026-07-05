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
    /// Whether this preset should appear in user-facing provider pickers
    /// (settings / onboarding). Defaults to `true` so the existing
    /// `presets` array keeps its public surface area; future passes can
    /// mark e.g. a DeepSeek key-pre-fill preset as `false` to hide it
    /// from the picker without touching call sites.
    public let isUserSelectable: Bool

    public init(
        id: String,
        name: String,
        defaultBaseURL: String,
        defaultModel: String,
        apiKeyURL: URL? = nil,
        blurb: String? = nil,
        isUserSelectable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.defaultBaseURL = defaultBaseURL
        self.defaultModel = defaultModel
        self.apiKeyURL = apiKeyURL
        self.blurb = blurb
        self.isUserSelectable = isUserSelectable
    }

    public static let presets: [LLMProvider] = [
        .init(
            id: "openai",
            name: "OpenAI",
            defaultBaseURL: "https://api.openai.com/v1",
            defaultModel: "gpt-4o-mini",
            apiKeyURL: URL(string: "https://platform.openai.com/api-keys"),
            blurb: "GPT-4o mini · 多语言 · Multilingual"
        ),
        .init(
            id: "deepseek",
            name: "DeepSeek",
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-v4-flash",
            apiKeyURL: URL(string: "https://platform.deepseek.com/api_keys"),
            blurb: "deepseek-v4-flash · 本地引擎内置 · Local engine built-in",
            // Local engine only — never shown in cloud-engine pickers.
            isUserSelectable: false
        ),
        .init(
            id: "qwen",
            name: "Qwen (DashScope)",
            defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            defaultModel: "qwen-plus",
            apiKeyURL: URL(string: "https://dashscope.console.aliyun.com/apiKey"),
            blurb: "通义千问 · OpenAI 兼容 · OpenAI-compatible"
        ),
        .init(
            id: "zhipu",
            name: "智谱 GLM · Zhipu",
            defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
            defaultModel: "glm-4-flash",
            apiKeyURL: URL(string: "https://bigmodel.cn/usercenter/apikeys"),
            blurb: "GLM-4-Flash · 中文优化 · Chinese-optimized"
        ),
        .init(
            id: "moonshot",
            name: "月之暗面 Moonshot",
            defaultBaseURL: "https://api.moonshot.cn/v1",
            defaultModel: "moonshot-v1-8k",
            apiKeyURL: URL(string: "https://platform.moonshot.cn/console/api-keys"),
            blurb: "Kimi · 长上下文 · Long context"
        ),
        .init(
            id: "custom",
            name: "Custom · 自定义",
            defaultBaseURL: "",
            defaultModel: "",
            blurb: "自建 / 任意 OpenAI 兼容端点 · Any OpenAI-compatible endpoint"
        )
    ]

    public static func provider(id: String) -> LLMProvider {
        presets.first(where: { $0.id == id }) ?? .presets[0]
    }

    /// Presets the user may pick in Settings / onboarding. DeepSeek is
    /// excluded — it is wired exclusively to the local engine.
    public static var userSelectablePresets: [LLMProvider] {
        presets.filter(\.isUserSelectable)
    }
}
