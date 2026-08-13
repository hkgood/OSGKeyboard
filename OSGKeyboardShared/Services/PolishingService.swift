// PolishingService.swift
// OSGKeyboard · Shared
//
// One-step intelligent polish combines ASR error correction, filler
// removal, and tone adaptation in a single LLM call. Keeping these
// operations merged avoids the latency and token cost of separate
// correction and polish requests; Typeless,
// Wispr Flow, and the "intelligent" rewrite literature all confirm
// the merged prompt performs just as well for everyday Chinese /
// English dictation while halving the network round-trip.
//
// Engine matrix:
//   - `engineMode == "cloud"`  → user's cloud ASR + user's cloud LLM (independent)
//   - `engineMode == "local"`  → on-device ASR + user's LLM polish
//   - Ultra-short / low-value short utterances skip the LLM entirely
//     (two-tier gate in TranscriptPostProcessor)
//   - Fun styles use full safeguards at light intensity and the
//     formatting-only creative path at heavy intensity
//   - Daily Chat keeps a local sparse-input safety brake
//   - Missing polish API key    → raw ASR + `.missingAPIKey` warning
//
// Caller-supplied `PolishContext` carries the per-call signals:
//   - `appContext`     code / email / chat / document / unknown
//   - `precedingText`  optional tail of the cursor's preceding text
//     for reference resolution
//
// The prompt is intentionally a single message; multi-message
// conversation history would let earlier hallucinations pollute
// later calls (see MIT 2026 "Do LLMs Benefit From Their Own Words?")
// and the user expectation is that each take is independent.

import Foundation

public actor PolishingService {

    public struct PolishOutcome: Sendable, Equatable {
        public let text: String
        public let qualityDegraded: Bool

        public init(text: String, qualityDegraded: Bool = false) {
            self.text = text
            self.qualityDegraded = qualityDegraded
        }
    }

    private struct RemotePolishResult: Sendable {
        let text: String
        let qualityDegraded: Bool
    }

    public enum PolishError: Error, Equatable {
        case noTranscript
        case timeout
        /// Polish LLM Keychain entry is empty for the resolved provider.
        case missingAPIKey
        /// The keychain was unreadable (device locked before first unlock)
        /// — the key likely EXISTS; treat as transient, never as "please
        /// re-enter your API key".
        case keychainLocked
    }

    /// What the LLM should do with the raw transcript. The
    /// polish path stays the default so every existing call site keeps
    /// its current behaviour — translation is opt-in via the `translate`
    /// case and gets a target-locale parameter baked into the prompt.
    public enum PolishMode: Equatable, Sendable {
        case polish
        case translate(targetLocaleId: String)
    }

    private let store: any ConfigurationStore
    private let timeout: TimeInterval
    /// Optional injected client (mostly for testing). When nil we build
    /// one from `store.makeClient()` per call.
    private let injectedClient: LLMClient?

    /// `timeout` is the baseline (shortest) per-request HTTP timeout,
    /// used as the floor for `effectiveTimeout(for:)`. It defaults to the
    /// shared `LLMClient.requestTimeout`. The safety-net timer adds its
    /// own slack on top of the length-scaled budget in `polishRemote`, so
    /// no `+1` is baked in here.
    public init(
        store: any ConfigurationStore = AppGroupStore(),
        client: LLMClient? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.store = store
        self.injectedClient = client
        self.timeout = timeout ?? LLMClientFactory.defaultRequestTimeout
    }

    /// Context-aware polish entry point. The optional
    /// `PolishContext` carries per-call signals (app context,
    /// intensity, preceding text). Translation is a separate concept
    /// (see `mode` below) so callers wanting the translate
    /// flow should keep using the override prompt / providerId
    /// overloads exposed by the host.
    public func polish(
        _ raw: String,
        mode: PolishMode = .polish,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil,
        context: PolishContext? = nil
    ) async throws -> String {
        try await performPolish(
            raw,
            mode: mode,
            systemPrompt: systemPrompt,
            providerIdOverride: providerIdOverride,
            context: context
        ).text
    }

    /// Additive result API for host pipelines that need to surface a conservative
    /// quality fallback without changing the established `polish` signature.
    public func polishWithOutcome(
        _ raw: String,
        mode: PolishMode = .polish,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil,
        context: PolishContext? = nil
    ) async throws -> PolishOutcome {
        try await performPolish(
            raw,
            mode: mode,
            systemPrompt: systemPrompt,
            providerIdOverride: providerIdOverride,
            context: context
        )
    }

    private func performPolish(
        _ raw: String,
        mode: PolishMode,
        systemPrompt: String?,
        providerIdOverride: String?,
        context: PolishContext?
    ) async throws -> PolishOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PolishError.noTranscript }

        let resolvedContext = resolveContext(override: context)
        let activeStyleID = store.activePolishStyleId

        // Two-tier short-circuit: ultra-short always; 5–10 CJK only for
        // low-value acks/closings (see TranscriptPostProcessor).
        if mode == .polish,
           systemPrompt == nil || systemPrompt?.isEmpty == true,
           TranscriptPostProcessor.shouldSkipLLM(
               for: trimmed,
               styleID: activeStyleID
           ) {
            FlowTrace.polish(
                "skippedLLM",
                "style=\(activeStyleID) intensity=\(store.polishIntensity.rawValue) "
                    + "inputLen=\(trimmed.count)"
            )
            return PolishOutcome(text: TranscriptPostProcessor.localClean(trimmed))
        }

        if injectedClient == nil {
            let providerId = Self.resolvedProviderId(store: store, providerIdOverride: providerIdOverride)
            let hasPolishKey = Self.hasPolishAPIKey(store: store, providerId: providerId)
            guard hasPolishKey else {
                if case .unavailable = Keychain.apiKeyOutcome(for: providerId, preferICloudSync: true) {
                    throw PolishError.keychainLocked
                }
                throw PolishError.missingAPIKey
            }
        }

        let remoteResult = try await polishRemote(
            trimmed,
            mode: mode,
            systemPrompt: systemPrompt,
            providerIdOverride: providerIdOverride,
            context: resolvedContext
        )

        // Translation and custom prompts bypass the polish post-processor.
        if mode != .polish || (systemPrompt != nil && !(systemPrompt?.isEmpty ?? true)) {
            return PolishOutcome(text: remoteResult.text)
        }

        return PolishOutcome(
            text: remoteResult.text,
            qualityDegraded: remoteResult.qualityDegraded
        )
    }

    private func resolveContext(override: PolishContext?) -> PolishContext {
        guard let override else {
            return PolishContext(
                appContext: store.detectedAppContext?.context ?? .unknown
            )
        }
        return override
    }

    private func polishRemote(
        _ trimmed: String,
        mode: PolishMode,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil,
        context: PolishContext
    ) async throws -> RemotePolishResult {
        let effectiveProviderId = Self.resolvedProviderId(
            store: store,
            providerIdOverride: providerIdOverride
        )
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
            let apiKey = Self.userAPIKey(
                store: store,
                providerId: effectiveProviderId
            )
            guard !apiKey.isEmpty else { throw PolishError.missingAPIKey }
            client = LLMClientFactory.make(
                providerId: effectiveProviderId,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model,
                thinkingEnabled: store.llmThinkingEnabled
            )
        }

        let prompt: String
        if let override = systemPrompt, !override.isEmpty {
            prompt = override
        } else {
            switch mode {
            case .polish:
                prompt = buildPrompt(
                    for: trimmed,
                    context: context,
                    providerId: effectiveProviderId
                )
            case .translate(let targetLocaleId):
                let target = TranslationLanguageCatalog.resolve(targetLocaleId)
                prompt = TranslationPrompt.make(
                    target: target,
                    providerId: effectiveProviderId,
                    appContext: context.appContext,
                    sourceText: trimmed
                )
            }
        }
        let budget = effectiveTimeout(for: trimmed)
        let usesHeavyFunPersonality = mode == .polish
            && (systemPrompt == nil || systemPrompt?.isEmpty == true)
            && PolishStylePackCatalog.usesFormattingOnlyPipeline(
                id: store.activePolishStyleId,
                intensity: store.polishIntensity
            )
        let firstOptions: LLMGenerationOptions = usesHeavyFunPersonality
            ? .funCreative
            : .polishDefault
        logPolishConfiguration(
            prompt: prompt,
            mode: mode,
            systemPromptOverride: systemPrompt,
            usesHeavyFunPersonality: usesHeavyFunPersonality,
            options: firstOptions,
            context: context,
            inputLength: trimmed.count
        )
        let userPayload: String
        if mode == .polish, systemPrompt == nil || systemPrompt?.isEmpty == true {
            userPayload = PolishPromptComposer.dictationUserPayload(trimmed)
        } else {
            userPayload = trimmed
        }
        let first = try await performLLMRequest(
            client: client,
            text: userPayload,
            prompt: prompt,
            timeout: budget,
            options: firstOptions
        )

        guard mode == .polish, systemPrompt == nil || systemPrompt?.isEmpty == true else {
            return RemotePolishResult(text: first, qualityDegraded: false)
        }

        // One prompt, one model request. Deterministic validation may reject a
        // result locally, but it never starts a second polish request.
        let activeStyle = PolishStylePackCatalog.resolve(
            id: store.activePolishStyleId,
            userCatalog: store.polishStyleCatalog
        )
        let firstCandidate = TranscriptPostProcessor.process(
            original: trimmed,
            llmOutput: first,
            allowsAddedEmoji: activeStyle.effectiveAllowsAddedEmoji
        )
        let firstViolations = PolishOutputValidator.validate(
            input: trimmed,
            output: firstCandidate,
            dictionary: store.personalDictionary
        )
        logViolations(firstViolations, attempt: 1)
        guard !firstViolations.isEmpty else {
            return RemotePolishResult(text: firstCandidate, qualityDegraded: false)
        }
        return RemotePolishResult(
            text: validationFallback(text: trimmed),
            qualityDegraded: true
        )
    }

    private func validationFallback(text: String) -> String {
        return TranscriptPostProcessor.minimalPolish(text)
    }

    private func performLLMRequest(
        client: any LLMClient,
        text: String,
        prompt: String,
        timeout: TimeInterval,
        options: LLMGenerationOptions
    ) async throws -> String {
        let safetyNet = timeout + 2
        do {
            return try await HardTimeout.run(seconds: safetyNet) {
                try await client.polish(
                    text,
                    systemPrompt: prompt,
                    timeout: timeout,
                    options: options
                )
            }
        } catch is CancellationError {
            throw PolishError.timeout
        }
    }

    /// Records which style, intensity, sampling profile and safeguard layers
    /// this request actually used. Without it, an unexpected reply can only be
    /// attributed to a style/intensity combination by guesswork.
    private func logPolishConfiguration(
        prompt: String,
        mode: PolishMode,
        systemPromptOverride: String?,
        usesHeavyFunPersonality: Bool,
        options: LLMGenerationOptions,
        context: PolishContext,
        inputLength: Int
    ) {
        let hasOverride = !(systemPromptOverride ?? "").isEmpty
        let fingerprint = PolishPromptComposer.fingerprint(of: prompt)
        let temperature = options.temperature.map { String(format: "%.2f", $0) } ?? "nil"
        FlowTrace.polish(
            "config",
            "style=\(store.activePolishStyleId) intensity=\(store.polishIntensity.rawValue) "
                + "mode=\(Self.polishModeLabel(mode)) heavyFun=\(usesHeavyFunPersonality ? 1 : 0) "
                + "override=\(hasOverride ? 1 : 0) temp=\(temperature) "
                + "inputLen=\(inputLength) beforeLen=\(context.precedingForPrompt?.count ?? 0) "
                + fingerprint.logLabel
        )
    }

    private static func polishModeLabel(_ mode: PolishMode) -> String {
        switch mode {
        case .polish: return "polish"
        case .translate: return "translate"
        }
    }

    private func logViolations(_ violations: [PolishViolation], attempt: Int) {
        guard !violations.isEmpty else { return }
        FlowTrace.polish(
            "validation",
            "attempt=\(attempt) " + violations.map(\.logLabel).joined(separator: ",")
        )
    }

    internal func buildPrompt(
        for text: String,
        context: PolishContext,
        providerId: String
    ) -> String {
        let dictionaryBlock = Self.mergedDictionaryBlock(
            dictionary: store.personalDictionary,
            supplement: context.dictionarySupplement
        )
        let useChinese = Self.shouldUseChineseGuidance(inputText: text, providerId: providerId)
        let style = PolishStylePackCatalog.resolve(
            id: store.activePolishStyleId,
            userCatalog: store.polishStyleCatalog
        )
        return PolishPromptComposer.compose(
            text: text,
            style: style,
            context: context,
            dictionaryBlock: dictionaryBlock,
            intensity: store.polishIntensity,
            useChineseGuidance: useChinese
        )
    }

    internal static func mergedDictionaryBlock(
        dictionary: PersonalDictionary,
        supplement: String?
    ) -> String {
        let base = dictionary.promptFragment()
        let extra = supplement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty { return extra }
        if extra.isEmpty { return base }
        return base + "\n" + extra
    }

    internal static let chineseNativeProviderIds: Set<String> = [
        "zhipu", "moonshot", "qwen", "deepseek", "ark", "minimax", "siliconflow", "mimo",
    ]

    internal static func shouldUseChineseGuidance(inputText: String, providerId: String) -> Bool {
        let ratio = TranscriptLanguageDetector.cjkRatio(inputText)
        if ratio >= 0.15 { return true }
        if ratio > 0 { return false }
        return chineseNativeProviderIds.contains(providerId)
    }

    /// Per-request HTTP timeout, scaled with transcript length. This is
    /// the *actual* value handed to `LLMClient.polish(timeout:)`, so long
    /// dictations (which generate long, listified, multi-paragraph output)
    /// are not cut off mid-generation by a fixed 15 s ceiling. Grows by
    /// ~10 s per 100 characters, capped at 120 s.
    ///
    /// Previously this value was computed but only used for the safety-net
    /// timer while the URLRequest stayed pinned at 15 s — the scaling was
    /// dead code and long transcripts timed out, falling back to the raw
    /// (unpolished, unsegmented) ASR text.
    internal func effectiveTimeout(for text: String) -> TimeInterval {
        if timeout == LLMClientFactory.defaultRequestTimeout {
            return FlowSessionKeys.polishTimeout(forCharacterCount: text.count)
        }
        let scaled = timeout + (Double(text.count) / 100.0) * 10.0
        // The cap participates in the keyboard-watchdog budget — see
        // `FlowSessionKeys.keyboardResultTimeout`. Raising it here without
        // going through that constant would silently break the invariant
        // "keyboard timeout > host worst case".
        return min(max(scaled, timeout), FlowSessionKeys.maxPolishTimeout)
    }

    internal static func resolvedProviderId(
        store: any ConfigurationStore,
        providerIdOverride: String?
    ) -> String {
        if let providerIdOverride {
            return providerIdOverride
        }
        return store.providerId
    }

    internal static func hasPolishAPIKey(store: any ConfigurationStore, providerId: String) -> Bool {
        !userAPIKey(store: store, providerId: providerId).isEmpty
    }

    private static func userAPIKey(
        store: any ConfigurationStore,
        providerId: String
    ) -> String {
        let key = providerId == store.providerId
            ? store.apiKey
            : Keychain.apiKey(for: providerId, preferICloudSync: true) ?? ""
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolve baseURL + model for polish and AI mode. Empty store fields fall
    /// back to the provider preset defaults so Settings remains the single
    /// source of truth for both dictation polish and AI keyboard questions.
    internal static func resolveLLMEndpoint(
        store: any ConfigurationStore,
        preset: LLMProvider,
        providerIdOverride: String?
    ) -> (baseURL: String, model: String) {
        if providerIdOverride != nil {
            return (preset.defaultBaseURL, preset.defaultModel)
        }
        let baseURL = store.baseURL.isEmpty ? preset.defaultBaseURL : store.baseURL
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
            return "Missing API key — fill it in Settings before polish can run."
        case .keychainLocked:
            return "API key unavailable while the device is locked — will work after unlock."
        }
    }
}
