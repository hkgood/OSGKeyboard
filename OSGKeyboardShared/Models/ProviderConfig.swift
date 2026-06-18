// ProviderConfig.swift
// OSGKeyboard · Shared
//
// User's LLM configuration. Persisted in App Group UserDefaults so both
// the main app and keyboard extension read the same values.
//
// `apiKey` is the exception: it lives in the Keychain (see
// `Keychain.swift`) for at-rest encryption. The first time this struct
// inits after upgrade, a legacy plaintext value from UserDefaults is
// migrated to the Keychain and removed from UserDefaults.

import Foundation
import Combine

public final class ProviderConfig: ObservableObject, @unchecked Sendable {
    public static let shared = ProviderConfig()

    private enum Key {
        static let providerId   = "config.providerId"
        static let baseURL      = "config.baseURL"
        // Legacy: apiKey used to live in UserDefaults before the
        // migration. We still read it once (see init below) and then
        // delete the entry, but no other code path touches this key.
        static let apiKeyLegacy = "config.apiKey"
        static let model        = "config.model"
        static let systemPrompt = "config.systemPrompt"
        static let modeId       = "config.modeId"
        static let localeId     = "config.localeId"
    }

    @Published public var providerId: String {
        didSet { defaults.set(providerId, forKey: Key.providerId) }
    }
    @Published public var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Key.baseURL) }
    }
    @Published public var apiKey: String {
        didSet {
            // Skip the round-trip on init — we read from Keychain and
            // writing the same value back is wasteful.
            guard oldValue != apiKey else { return }
            do {
                try Keychain.setAPIKey(apiKey)
            } catch {
                #if DEBUG
                print("⚠️ [OSGKeyboard] Keychain write failed: \(error)")
                #endif
            }
        }
    }
    @Published public var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }
    @Published public var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) }
    }
    @Published public var modeId: String {
        didSet { defaults.set(modeId, forKey: Key.modeId) }
    }
    @Published public var localeId: String {
        didSet { defaults.set(localeId, forKey: Key.localeId) }
    }

    public var isConfigured: Bool {
        !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    /// The system prompt the user *sees* in the editor — fall back to the
    /// provider-aware default from `AppGroupStore` when nothing is set.
    public var defaultSystemPrompt: String {
        AppGroupStore.defaultSystemPrompt(for: providerId)
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        let pid = defaults.string(forKey: Key.providerId) ?? "openai"
        let preset = LLMProvider.provider(id: pid)
        self.providerId   = pid
        self.baseURL      = defaults.string(forKey: Key.baseURL)    ?? preset.defaultBaseURL

        // Resolve the API key with a one-shot migration from the legacy
        // UserDefaults slot. After this runs once, `Key.apiKeyLegacy`
        // is empty in the suite and all subsequent reads go through the
        // Keychain.
        self.apiKey = ProviderConfig.resolveAPIKey(defaults: defaults)

        self.model        = defaults.string(forKey: Key.model)      ?? preset.defaultModel
        self.systemPrompt = defaults.string(forKey: Key.systemPrompt)
            ?? AppGroupStore.defaultSystemPrompt(for: pid)
        self.modeId       = defaults.string(forKey: Key.modeId)     ?? "polish"
        self.localeId     = defaults.string(forKey: Key.localeId)   ?? "auto"
    }

    /// Read the API key from the Keychain, falling back to a one-time
    /// migration from the legacy UserDefaults slot.
    private static func resolveAPIKey(defaults: UserDefaults) -> String {
        if let stored = Keychain.apiKey(), !stored.isEmpty {
            return stored
        }
        if let legacy = defaults.string(forKey: Key.apiKeyLegacy),
           !legacy.isEmpty {
            try? Keychain.setAPIKey(legacy)
            defaults.removeObject(forKey: Key.apiKeyLegacy)
            return legacy
        }
        return ""
    }

    public func apply(preset: LLMProvider) {
        // Capture the *previous* provider id BEFORE we mutate, so the
        // system-prompt reset check below can compare against the actual
        // prior default.
        let oldId = providerId
        providerId = preset.id
        if !preset.defaultBaseURL.isEmpty {
            baseURL = preset.defaultBaseURL
        }
        if !preset.defaultModel.isEmpty {
            model = preset.defaultModel
        }
        // When switching providers, reset the system prompt to the new
        // provider's default — otherwise the user is left editing a
        // Chinese prompt on a US-English model.
        if systemPrompt.isEmpty
            || systemPrompt == AppGroupStore.defaultSystemPrompt(for: oldId) {
            systemPrompt = AppGroupStore.defaultSystemPrompt(for: preset.id)
        }
    }

    public func reset() {
        providerId = "openai"
        let preset = LLMProvider.provider(id: "openai")
        baseURL = preset.defaultBaseURL
        apiKey = ""
        model = preset.defaultModel
        systemPrompt = AppGroupStore.defaultSystemPrompt(for: "openai")
    }
}
