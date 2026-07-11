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
            id: "ark",
            name: "火山方舟 Ark",
            defaultBaseURL: "https://ark.cn-beijing.volces.com/api/v3",
            defaultModel: "deepseek-v3-2-251201",
            apiKeyURL: URL(string: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey"),
            blurb: "豆包 / DeepSeek · OpenAI 兼容 · OpenAI-compatible"
        ),
        .init(
            id: "deepseek",
            name: "DeepSeek",
            defaultBaseURL: "https://api.deepseek.com/v1",
            defaultModel: "deepseek-v4-flash",
            apiKeyURL: URL(string: "https://platform.deepseek.com/api_keys"),
            blurb: "deepseek-v4-flash · 本地引擎可内置 · Local engine optional built-in"
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
            id: "siliconflow",
            name: "硅基流动 SiliconFlow",
            defaultBaseURL: "https://api.siliconflow.cn/v1",
            defaultModel: "Qwen/Qwen2.5-7B-Instruct",
            apiKeyURL: URL(string: "https://cloud.siliconflow.cn/account/ak"),
            blurb: "多模型聚合 · OpenAI 兼容 · OpenAI-compatible"
        ),
        .init(
            id: "groq",
            name: "Groq",
            defaultBaseURL: "https://api.groq.com/openai/v1",
            defaultModel: "llama-3.3-70b-versatile",
            apiKeyURL: URL(string: "https://console.groq.com/keys"),
            blurb: "超低延迟 LPU · Ultra-low latency"
        ),
        .init(
            id: "minimax",
            name: "MiniMax",
            defaultBaseURL: "https://api.minimaxi.com/v1",
            defaultModel: "MiniMax-M2.5",
            apiKeyURL: URL(string: "https://platform.minimaxi.com/user-center/basic-information"),
            blurb: "MiniMax-M2.5 · 中文优化 · Chinese-optimized"
        ),
        .init(
            id: "mimo",
            name: "小米 MiMo",
            defaultBaseURL: "https://api.xiaomimimo.com/v1",
            defaultModel: "mimo-v2.5",
            apiKeyURL: URL(string: "https://platform.xiaomimimo.com"),
            blurb: "mimo-v2.5 · 中文优化 · Chinese-optimized"
        ),
        .init(
            id: "openrouter",
            name: "OpenRouter",
            defaultBaseURL: "https://openrouter.ai/api/v1",
            defaultModel: "qwen/qwen3-coder:free",
            apiKeyURL: URL(string: "https://openrouter.ai/keys"),
            blurb: "多模型路由 · Model routing · OpenAI-compatible"
        ),
        .init(
            id: "gemini",
            name: "Google Gemini",
            defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            defaultModel: "gemini-2.5-flash",
            apiKeyURL: URL(string: "https://aistudio.google.com/apikey"),
            blurb: "Gemini 2.5 Flash · OpenAI 兼容端点"
        ),
        .init(
            id: "anthropic",
            name: "Anthropic Claude",
            defaultBaseURL: "https://api.anthropic.com/v1",
            defaultModel: "claude-sonnet-4-6",
            apiKeyURL: URL(string: "https://console.anthropic.com/settings/keys"),
            blurb: "Claude Sonnet · Messages API"
        ),
        .init(
            id: "xai",
            name: "xAI Grok",
            defaultBaseURL: "https://api.x.ai/v1",
            defaultModel: "grok-3-mini",
            apiKeyURL: URL(string: "https://console.x.ai"),
            blurb: "Grok · OpenAI 兼容 · OpenAI-compatible"
        ),
        .init(
            id: "mistral",
            name: "Mistral AI",
            defaultBaseURL: "https://api.mistral.ai/v1",
            defaultModel: "mistral-small-latest",
            apiKeyURL: URL(string: "https://console.mistral.ai/api-keys"),
            blurb: "Mistral Small · 欧洲托管 · EU-hosted"
        ),
        .init(
            id: "cometapi",
            name: "CometAPI",
            defaultBaseURL: "https://api.cometapi.com/v1",
            defaultModel: "gpt-4o",
            apiKeyURL: URL(string: "https://api.cometapi.com"),
            blurb: "多模型聚合 · OpenAI 兼容"
        ),
        .init(
            id: "alibabaCoding",
            name: "阿里 Coding Plan",
            defaultBaseURL: "https://coding-intl.dashscope.aliyuncs.com/v1",
            defaultModel: "qwen3-coder-plus",
            apiKeyURL: URL(string: "https://dashscope.console.aliyun.com/apiKey"),
            blurb: "通义 Coder · 代码润色 · Coding polish"
        ),
        .init(
            id: "codingPlanX",
            name: "CodingPlanX",
            defaultBaseURL: "https://api.codingplanx.ai/v1",
            defaultModel: "gpt-5-mini",
            apiKeyURL: URL(string: "https://codingplanx.ai"),
            blurb: "CodingPlanX · OpenAI 兼容"
        ),
        // MARK: - ASR-only presets (hidden from polish picker)
        .init(
            id: "volcengine",
            name: "火山引擎 Volcengine",
            defaultBaseURL: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
            defaultModel: "volc.seedasr.sauc.duration",
            apiKeyURL: URL(string: "https://console.volcengine.com/speech"),
            blurb: "流式大模型 ASR · API Key 填 appId:accessToken[:resourceId]",
            isUserSelectable: false
        ),
        .init(
            id: "bailian",
            name: "百炼实时 ASR",
            defaultBaseURL: "wss://dashscope.aliyuncs.com/api-ws/v1/inference/",
            defaultModel: "fun-asr-realtime",
            apiKeyURL: URL(string: "https://dashscope.console.aliyun.com/apiKey"),
            blurb: "Fun-ASR Realtime · 百炼词表",
            isUserSelectable: false
        ),
        .init(
            id: "whisper",
            name: "Whisper (OpenAI)",
            defaultBaseURL: "https://api.openai.com/v1",
            defaultModel: "whisper-1",
            apiKeyURL: URL(string: "https://platform.openai.com/api-keys"),
            blurb: "whisper-1 · 经典 Whisper 端点",
            isUserSelectable: false
        ),
        .init(
            id: "codex_oauth",
            name: "Codex OAuth",
            defaultBaseURL: "",
            defaultModel: "gpt-5.3-codex-spark",
            blurb: "ChatGPT Codex OAuth · 暂不支持",
            isUserSelectable: false
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

    /// Presets the user may pick in Settings / onboarding.
    public static var userSelectablePresets: [LLMProvider] {
        presets.filter(\.isUserSelectable)
    }

    /// Cloud ASR presets (explicit allowlist — polish-only providers excluded).
    public static var asrSelectablePresets: [LLMProvider] {
        presets.filter { CloudASRModelCatalog.supportsCloudASRSelection(providerId: $0.id) }
    }
}
