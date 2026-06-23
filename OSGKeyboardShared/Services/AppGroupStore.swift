// AppGroupStore.swift
// OSGKeyboard · Shared
//
// Convenience wrapper around App Group UserDefaults for non-Published reads.
// Used by the keyboard extension (no SwiftUI) to read config without
// instantiating an ObservableObject.
//
// `apiKey` is NOT read from UserDefaults — see `Keychain.swift`. We
// share access between the host app and the keyboard extension via a
// shared keychain-access-group declared in both targets' entitlements.

import Foundation

public struct AppGroupStore: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
            return
        }
        // Never hard-crash on implicit construction sites (e.g. default
        // service initializers). If App Group is unavailable, use .standard
        // so callers can still surface a user-facing setup error.
        self.defaults = AppGroup.isAvailable ? AppGroup.defaults : .standard
    }

    // MARK: - Keys

    private enum Key {
        static let providerId      = "config.providerId"
        static let baseURL         = "config.baseURL"
        static let model           = "config.model"
        static let systemPrompt    = "config.systemPrompt"
        static let modeId          = "config.modeId"
        static let localeId        = "config.localeId"
        static let engineMode       = "config.engineMode"
        static let localASRBackend  = "config.localASRBackend"
        static let uiLanguage       = "config.uiLanguage"
    }

    // MARK: - Reads

    public var providerId: String {
        defaults.string(forKey: Key.providerId) ?? "openai"
    }

    public var baseURL: String {
        defaults.string(forKey: Key.baseURL) ?? LLMProvider.provider(id: providerId).defaultBaseURL
    }

    /// API key lives in the Keychain (cross-process, encrypted at rest).
    /// Returns "" when nothing is stored so the LLMClient can surface a
    /// `noAPIKey` error rather than firing off an obviously-bad request.
    public var apiKey: String {
        Keychain.apiKey() ?? ""
    }

    public var model: String {
        defaults.string(forKey: Key.model) ?? LLMProvider.provider(id: providerId).defaultModel
    }

    public var systemPrompt: String {
        defaults.string(forKey: Key.systemPrompt) ?? Self.defaultSystemPrompt(for: providerId)
    }

    public var modeId: String {
        defaults.string(forKey: Key.modeId) ?? "polish"
    }

    public var localeId: String {
        defaults.string(forKey: Key.localeId) ?? "auto"
    }

    /// "local" → on-device ASR only (raw transcript delivery).
    /// "cloud" → ASR + LLM polish (default behaviour).
    public var engineMode: String {
        defaults.string(forKey: Key.engineMode) ?? "cloud"
    }

    /// Which on-device ASR engine backs the "local" engine mode. Falls
    /// back to the iOS SpeechAnalyzer path so legacy installs (which
    /// never wrote this key) keep working.
    public var localASRBackend: LocalASRBackend {
        let raw = defaults.string(forKey: Key.localASRBackend) ?? LocalASRBackend.speechAnalyzer.rawValue
        return LocalASRBackend(rawValue: raw) ?? .speechAnalyzer
    }

    /// Host-app UI language override (`auto` / `en` / `zh-Hans`).
    public var uiLanguage: AppUILanguage {
        AppUILanguage.fromStored(defaults.string(forKey: Key.uiLanguage))
    }

    // MARK: - Writes

    public func setModeId(_ id: String) {
        defaults.set(id, forKey: Key.modeId)
    }

    public func setLocaleId(_ id: String) {
        defaults.set(id, forKey: Key.localeId)
    }

    public func setEngineMode(_ mode: String) {
        defaults.set(mode, forKey: Key.engineMode)
    }

    public func setLocalASRBackend(_ backend: LocalASRBackend) {
        defaults.set(backend.rawValue, forKey: Key.localASRBackend)
    }

    public func setUILanguage(_ language: AppUILanguage) {
        defaults.set(language.rawValue, forKey: Key.uiLanguage)
    }

    // MARK: - Client

    public func makeClient() -> LLMClient {
        OpenAICompatibleClient(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model
        )
    }

    // MARK: - Defaults

    /// Per-provider default system prompt. We bias the prompt by the
    /// provider's *primary* language so Chinese LLMs naturally return
    /// Chinese for Chinese input, and English LLMs stay terse.
    public static func defaultSystemPrompt(for providerId: String) -> String {
        switch providerId {
        case "zhipu", "moonshot", "qwen", "deepseek":
            return """
            你是一位语音输入润色助手。请将用户的口述改写为干净的中文(或英文)书面文字:
            1) 保留原意,不编造事实;保持输入语言。
            2) 添加恰当的标点、大小写、段落。
            3) 当用户枚举"第一…第二…第三…"时,使用 markdown 列表。
            4) 简洁,不超出原长 1.5 倍;可去掉无意义的口头禅(嗯、啊、那个)。
            5) 只输出润色后的正文,不要解释、不要加引号。
            """
        default:
            return """
            You are a voice-input polishing assistant. The user has spoken informally; rewrite their dictation as clean written text:
            1) Preserve the user's original intent and meaning; do not invent facts.
            2) Add proper punctuation, capitalization, and paragraph breaks.
            3) When the user enumerates items ("first ... second ... third"), output a markdown list.
            4) Keep the output concise — do not exceed 1.5x the spoken length. Drop filler words (um, uh, like).
            5) Output in the same language as the input. No quotes, no explanation, no preamble.
            """
        }
    }
}
