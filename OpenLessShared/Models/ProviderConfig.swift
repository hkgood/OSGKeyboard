// ProviderConfig.swift
// OSGKeyboard · Shared
//
// User's LLM configuration. Persisted in App Group UserDefaults so both
// the main app and keyboard extension read the same values.

import Foundation
import Combine

public final class ProviderConfig: ObservableObject, @unchecked Sendable {
    public static let shared = ProviderConfig()

    // Storage keys
    private enum Key {
        static let providerId   = "config.providerId"
        static let baseURL      = "config.baseURL"
        static let apiKey       = "config.apiKey"
        static let model        = "config.model"
        static let systemPrompt = "config.systemPrompt"
    }

    @Published public var providerId: String {
        didSet { defaults.set(providerId, forKey: Key.providerId) }
    }

    @Published public var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Key.baseURL) }
    }

    @Published public var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Key.apiKey) }
    }

    @Published public var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }

    @Published public var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) }
    }

    public var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    public let defaultSystemPrompt = """
    You are a voice-input polishing assistant. The user has spoken informally; rewrite their dictation as clean written text:
    1) Preserve the user's original intent and meaning; do not invent facts.
    2) Add proper punctuation, capitalization, and paragraph breaks.
    3) When the user enumerates items ("first ... second ... third"), output a markdown list.
    4) Keep the output concise — do not exceed 1.5x the spoken length.
    5) Output in the same language as the input.
    """

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        self.providerId   = defaults.string(forKey: Key.providerId) ?? "openai"
        self.baseURL      = defaults.string(forKey: Key.baseURL)    ?? LLMProvider.provider(id: "openai").defaultBaseURL
        self.apiKey       = defaults.string(forKey: Key.apiKey)     ?? ""
        self.model        = defaults.string(forKey: Key.model)      ?? LLMProvider.provider(id: "openai").defaultModel
        self.systemPrompt = defaults.string(forKey: Key.systemPrompt) ?? defaultSystemPrompt
    }

    public func apply(preset: LLMProvider) {
        providerId = preset.id
        if !preset.defaultBaseURL.isEmpty {
            baseURL = preset.defaultBaseURL
        }
        if !preset.defaultModel.isEmpty {
            model = preset.defaultModel
        }
    }

    public func reset() {
        providerId = "openai"
        let preset = LLMProvider.provider(id: "openai")
        baseURL = preset.defaultBaseURL
        apiKey = ""
        model = preset.defaultModel
        systemPrompt = defaultSystemPrompt
    }
}
