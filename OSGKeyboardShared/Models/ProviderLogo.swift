// ProviderLogo.swift
// OSGKeyboard · Shared
//
// Maps a provider id to its asset-catalog logo name. Shared by the iOS
// app and the macOS menu-bar app so both show identical brand marks.

import Foundation

public enum ProviderLogo {
    /// Asset name for the provider's logo, or `nil` when there is no bundled logo.
    public static func assetName(for providerId: String) -> String? {
        switch providerId {
        case "openai", "whisper": return "openai"
        case "deepseek": return "deepseek"
        case "qwen", "bailian", "alibabaCoding": return "qwen"
        case "moonshot": return "moonshot"
        case "zhipu": return "zhipu"
        case "mimo": return "mimo"
        case "ark", "volcengine": return "ark"
        case "siliconflow": return "siliconflow"
        case "groq": return "groq"
        case "minimax": return "minimax"
        case "openrouter": return "openrouter"
        case "gemini": return "gemini"
        case "anthropic": return "anthropic"
        case "xai": return "xai"
        case "mistral": return "mistral"
        case "cometapi": return "cometapi"
        case "codingPlanX": return "codingplanx"
        case "codex_oauth": return "openai"
        case "apple": return "apple"
        case "custom": return "custom"
        default: return nil
        }
    }
}
