// AppGroupStore.swift
// OSGKeyboard · Shared
//
// Convenience wrapper around App Group UserDefaults for non-Published reads.
// Used by the keyboard extension (no SwiftUI) to read config without
// instantiating an ObservableObject.

import Foundation

public struct AppGroupStore: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    public var providerId: String {
        defaults.string(forKey: "config.providerId") ?? "openai"
    }

    public var baseURL: String {
        defaults.string(forKey: "config.baseURL") ?? LLMProvider.provider(id: "openai").defaultBaseURL
    }

    public var apiKey: String {
        defaults.string(forKey: "config.apiKey") ?? ""
    }

    public var model: String {
        defaults.string(forKey: "config.model") ?? LLMProvider.provider(id: "openai").defaultModel
    }

    public var systemPrompt: String {
        defaults.string(forKey: "config.systemPrompt")
            ?? "You are a voice-input polishing assistant. Rewrite the user's dictation as clean written text. Preserve intent. Add punctuation and structure. Do not invent facts. Output in the same language as the input."
    }

    public func makeClient() -> LLMClient {
        OpenAICompatibleClient(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model
        )
    }
}
