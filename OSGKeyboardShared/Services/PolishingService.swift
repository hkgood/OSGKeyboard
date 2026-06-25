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
//     `localModeCloudPolishEnabled == false` → ASR-only, return raw.
//   - `engineMode == "local"`,
//     `localModeCloudPolishEnabled == true`  → polish via the user's LLM
//     (DeepSeek by default). The local engine gains stronger accuracy on
//     noisy / dialectal Chinese at the cost of one cloud round-trip.
//     If the user hasn't entered an API key the call falls back to the
//     raw transcript and surfaces a warning so the keyboard can show
//     the "fill in your key" hint.

import Foundation

public actor PolishingService {

    public enum PolishError: Error, Equatable {
        case noTranscript
        case timeout
        /// v0.2.0: local engine + cloud-polish-on, but the user hasn't
        /// saved an API key in the Keychain. Caller surfaces an Alert
        /// telling them to fill it in; we deliver the raw transcript
        /// so no data is lost.
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

        // Local engine: ASR-only unless the user opted into cloud
        // polish via `localModeCloudPolishEnabled`. The cloud polish
        // path still requires an API key; if the Keychain is empty we
        // fall back to the raw transcript and throw `missingAPIKey`
        // so the UI can surface the "fill in your key" hint.
        if store.engineMode == "local" {
            guard store.localModeCloudPolishEnabled else { return trimmed }
            guard !store.apiKey.isEmpty else {
                throw PolishError.missingAPIKey
            }
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
            let baseURL = store.baseURL.isEmpty ? preset.defaultBaseURL : store.baseURL
            // Pre-existing typo fix: the user-overridden `store.model`
            // path was returning `preset.defaultModel` on both branches,
            // silently ignoring the user's custom model field. Restore
            // the asymmetry so the user override actually wins.
            let model = store.model.isEmpty ? preset.defaultModel : store.model
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
        let prompt = resolvedSystemPrompt(for: mode, override: systemPrompt)
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
    private func resolvedSystemPrompt(for mode: PolishMode, override: String? = nil) -> String {
        if let override, !override.isEmpty {
            return override
        }
        switch mode {
        case .polish:
            return store.systemPrompt
        case .translate(let targetLocaleId):
            let target = TranslationLanguageCatalog.resolve(targetLocaleId)
            let pid = store.providerId
            return TranslationPrompt.make(target: target, providerId: pid)
        }
    }

    /// Scale polish budget with transcript length (3-minute Flow utterances).
    private func effectiveTimeout(for text: String) -> TimeInterval {
        let scaled = timeout + (Double(text.count) / 200.0) * 2.0
        return min(max(scaled, timeout), 120)
    }
}
