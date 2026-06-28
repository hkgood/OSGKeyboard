// PolishingService.swift
// OSGKeyboard · Shared
//
// Takes raw ASR transcript and runs it through the user's configured LLM
// to produce polished, well-punctuated text. Falls back to the raw transcript
// if the LLM call fails or times out.
//
// Engine matrix:
//   - `engineMode == "cloud"`  → always polish (cloud engine's whole point).
//   - `engineMode == "local"`,
//     cloud polish disabled → ASR-only, return raw.
//   - `engineMode == "local"`,
//     cloud polish enabled → DeepSeek LLM step (polish or translate).
//     Translation uses `.translate` + `TranslationPrompt`; polish uses
//     the default system prompt. Missing preconfigured DeepSeek key
//     throws `missingAPIKey` and callers deliver raw + warning.

import Foundation

public actor PolishingService {

    public enum PolishError: Error, Equatable {
        case noTranscript
        case timeout
        /// Local engine DeepSeek step: `PreconfiguredKeys.deepseek` is
        /// still the repo placeholder, or cloud engine Keychain is empty.
        case missingAPIKey
    }

    /// v0.2.1: what the LLM should do with the raw transcript. The
    /// polish path stays the default so every existing call site keeps
    /// its current behaviour — translation is opt-in via the `translate`
    /// case and gets a target-locale parameter baked into the prompt.
    public enum PolishMode: Equatable, Sendable {
        case polish
        case translate(targetLocaleId: String)
    }

    private let store: AppGroupStore
    private let timeout: TimeInterval
    /// Optional injected client (mostly for testing). When nil we build
    /// one from `store.makeClient()` per call.
    private let injectedClient: LLMClient?

    /// Default `timeout` is `LLMClient.requestTimeout + 1` second so the
    /// safety-net `withThrowingTaskGroup` never wins the race against
    /// the URL request itself; if the request times out cleanly the
    /// network error reaches us first. The +1 is the single point of
    /// slack between the two clocks — keep it here, not in `LLMClient`.
    public init(
        store: AppGroupStore = AppGroupStore(),
        client: LLMClient? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.store = store
        self.injectedClient = client
        self.timeout = timeout ?? (LLMClientFactory.defaultRequestTimeout + 1)
    }

    /// v0.2.1 follow-up: `providerIdOverride` lets callers pin the
    /// remote polish step to a specific provider (the local engine
    /// pins to DeepSeek regardless of the user's chosen cloud
    /// provider). Pass `nil` to honor `store.providerId` as before.
    public func polish(
        _ raw: String,
        mode: PolishMode = .polish,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil
    ) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PolishError.noTranscript }

        // Local engine: ASR-only unless cloud polish is enabled
        // (translation is a sub-option of that LLM step).
        if store.engineMode == "local" {
            guard store.shouldRunCloudLLMStep else { return trimmed }
            return try await polishRemote(
                trimmed,
                mode: mode,
                systemPrompt: systemPrompt,
                providerIdOverride: providerIdOverride
            )
        }

        return try await polishRemote(
            trimmed,
            mode: mode,
            systemPrompt: systemPrompt,
            providerIdOverride: providerIdOverride
        )
    }

    private func polishRemote(
        _ trimmed: String,
        mode: PolishMode,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil
    ) async throws -> String {
        // v0.2.1 follow-up: when the caller pins a provider id (the
        // local engine pins DeepSeek) we still want to honor the
        // injected test client, but we have to re-derive the
        // preset/baseURL/model/apiKey quartet from the *override* so
        // the injected client gets the right values when it's nil.
        let effectiveProviderId = providerIdOverride ?? store.providerId
        let client: LLMClient
        if let injectedClient {
            client = injectedClient
        } else {
            let preset = LLMProvider.provider(id: effectiveProviderId)
            let (baseURL, model) = Self.resolveLLMEndpoint(
                store: store,
                preset: preset,
                providerIdOverride: providerIdOverride
            )
            let apiKey: String
            if effectiveProviderId == "deepseek" {
                let preconfigured = PreconfiguredKeys.deepseek
                if preconfigured == "TODO_FILL_LATER_DEEPSEEK_KEY" {
                    // Placeholder still in place — refuse the round-
                    // trip so the UI can surface a "build not
                    // configured" hint instead of a 401.
                    throw PolishError.missingAPIKey
                }
                apiKey = preconfigured
            } else {
                apiKey = store.apiKey
            }
            client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey, model: model)
        }
        let prompt = resolvedSystemPrompt(
            for: mode,
            override: systemPrompt,
            providerId: effectiveProviderId
        )
        let budget = effectiveTimeout(for: trimmed)

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await client.polish(trimmed, systemPrompt: prompt)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(budget * 1_000_000_000))
                throw PolishError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// v0.2.1: pick the right system prompt for the requested mode.
    /// Translation mode swaps in the parameterized translate-and-polish
    /// prompt (see `TranslationPrompt.make`); polish mode keeps the
    /// existing `store.systemPrompt` behaviour so every other call site
    /// is byte-identical to before. An explicit `override` wins over
    /// both paths so callers (and tests) can pin a specific prompt.
    private func resolvedSystemPrompt(
        for mode: PolishMode,
        override: String? = nil,
        providerId: String? = nil
    ) -> String {
        if let override, !override.isEmpty {
            return override
        }
        switch mode {
        case .polish:
            return store.resolvedPolishSystemPrompt(providerId: providerId)
        case .translate(let targetLocaleId):
            let target = TranslationLanguageCatalog.resolve(targetLocaleId)
            let pid = providerId ?? store.providerId
            return TranslationPrompt.make(
                target: target,
                providerId: pid,
                scenarioId: store.polishScenarioId,
                uiLanguage: store.uiLanguage
            )
        }
    }

    /// Scale polish budget with transcript length (3-minute Flow utterances).
    private func effectiveTimeout(for text: String) -> TimeInterval {
        let scaled = timeout + (Double(text.count) / 200.0) * 2.0
        return min(max(scaled, timeout), 120)
    }

    /// Picks base URL + model for one remote polish call.
    ///
    /// When `providerIdOverride` is set (local engine pins DeepSeek),
    /// always use that preset's defaults so cloud-engine settings
    /// (e.g. Qwen base URL saved while testing cloud mode) are not
    /// mixed with the pinned provider's API key. Cloud engine passes
    /// `nil` and keeps honoring `store.baseURL` / `store.model`.
    internal static func resolveLLMEndpoint(
        store: AppGroupStore,
        preset: LLMProvider,
        providerIdOverride: String?
    ) -> (baseURL: String, model: String) {
        if providerIdOverride != nil {
            return (preset.defaultBaseURL, preset.defaultModel)
        }
        let baseURL = store.baseURL.isEmpty ? preset.defaultBaseURL : store.baseURL
        // Pre-existing typo fix: the user-overridden `store.model`
        // path was returning `preset.defaultModel` on both branches,
        // silently ignoring the user's custom model field. Restore
        // the asymmetry so the user override actually wins.
        let model = store.model.isEmpty ? preset.defaultModel : store.model
        return (baseURL, model)
    }
}

extension PolishingService.PolishError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noTranscript:
            return "No transcript to polish."
        case .timeout:
            return "LLM polish timed out."
        case .missingAPIKey:
            return "Missing API key (local: set PreconfiguredKeys.deepseek; cloud: Settings API key)."
        }
    }
}
