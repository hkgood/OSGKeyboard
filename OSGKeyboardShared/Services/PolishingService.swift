// PolishingService.swift
// OSGKeyboard · Shared
//
// v0.3.0 rewrite: one-step "intelligent" polish that combines ASR
// error correction, filler removal, and tone adaptation in a single
// LLM call. The previous design was two separate steps (correction
// then polish) which doubled latency and token cost; Typeless,
// Wispr Flow, and the "intelligent" rewrite literature all confirm
// the merged prompt performs just as well for everyday Chinese /
// English dictation while halving the network round-trip.
//
// Engine matrix:
//   - `engineMode == "cloud"`  → always polish
//   - `engineMode == "local"`,
//     cloud polish disabled → ASR-only, return raw.
//   - `engineMode == "local"`,
//     cloud polish enabled → DeepSeek LLM step (polish or translate).
//     Translation uses `.translate` + `TranslationPrompt`; polish uses
//     the default system prompt. Missing preconfigured DeepSeek key
//     throws `missingAPIKey` and callers deliver raw + warning.
//   - `polishIntensity == .off`               → ASR-only, return raw,
//     regardless of engine mode
//   - Missing API key                          → return raw + throw
//     `.missingAPIKey` so the caller can show the "fill in your key"
//     hint inline
//
// Caller-supplied `PolishContext` carries the per-call signals:
//   - `appContext`     code / email / chat / document / unknown
//   - `intensity`      off / light / medium / heavy (per-call
//     override; default is the user-configured value)
//   - `precedingText`  optional tail of the cursor's preceding text
//     for reference resolution
//
// The prompt is intentionally a single message; multi-message
// conversation history would let earlier hallucinations pollute
// later calls (see MIT 2026 "Do LLMs Benefit From Their Own Words?")
// and the user expectation is that each take is independent.

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

/// v0.3.0: context-aware polish entry point. The optional
    /// `PolishContext` carries per-call signals (app context,
    /// intensity, preceding text). Translation is a separate concept
    /// (see `mode` below) so callers wanting the v0.2.1 translate
    /// flow should keep using the override prompt / providerId
    /// overloads exposed by the host.
    public func polish(
        _ raw: String,
        mode: PolishMode = .polish,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil,
        context: PolishContext? = nil
    ) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PolishError.noTranscript }

        // Resolve per-call context: per-call override wins over the
        // user-configured App Group value.
        let resolvedContext = resolveContext(override: context)

        // "off" intensity never calls the LLM, regardless of engine
        // or mode. This lets users opt into "transcribe only" with
        // one tap without having to flip the engine mode or pick a
        // translation off-locale.
        if resolvedContext.intensity == .off {
            return trimmed
        }

        // Local engine + cloud-polish-off: pure ASR, no LLM.
        if store.engineMode == "local" {
            guard store.shouldRunCloudLLMStep else { return trimmed }
        } else {
            // Cloud engine needs an API key.
            guard !store.apiKey.isEmpty else {
                throw PolishError.missingAPIKey
            }
        }

        return try await polishRemote(
            trimmed,
            mode: mode,
            systemPrompt: systemPrompt,
            providerIdOverride: providerIdOverride,
            context: resolvedContext
        )
    }

    /// Build the final `PolishContext` for this call. Per-call
    /// overrides take precedence; otherwise we read the user-configured
    /// values out of the App Group (so the keyboard extension's
    /// `PolishingService` instance does not need to know about
    /// `ProviderConfig`).
    private func resolveContext(override: PolishContext?) -> PolishContext {
        guard let override else {
            return PolishContext(
                appContext: store.detectedAppContext?.context ?? .unknown,
                intensity: store.polishIntensity
            )
        }
        // If the override leaves a field at its default-when-nil
        // value, fall back to the App Group value. Today every
        // `PolishContext` field is non-optional so this branch
        // simply forwards; kept for future-proofing.
        return override
    }

    private func polishRemote(
        _ trimmed: String,
        mode: PolishMode,
        systemPrompt: String? = nil,
        providerIdOverride: String? = nil,
        context: PolishContext
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
        // Polish-mode callers (and translation-mode callers that
        // haven't supplied an explicit override) get the new
        // "intelligent" prompt that uses `PolishContext.appContext`,
        // `intensity`, and the personal dictionary. Translation-mode
        // callers keep the v0.2.1 `TranslationPrompt` path so the
        // translate-and-polish output contract doesn't change.
        let prompt: String
        if let override = systemPrompt, !override.isEmpty {
            prompt = override
        } else {
            switch mode {
            case .polish:
                prompt = buildPrompt(for: trimmed, context: context)
            case .translate(let targetLocaleId):
                let target = TranslationLanguageCatalog.resolve(targetLocaleId)
                prompt = TranslationPrompt.make(
                    target: target,
                    providerId: effectiveProviderId,
                    scenarioId: store.polishScenarioId,
                    uiLanguage: store.uiLanguage
                )
            }
        }
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

    /// Build the one-step "intelligent" prompt. The structure is:
    ///   1. Role
    ///   2. Three numbered tasks (correction, polish, style)
    ///   3. Hard rules (do-not-modify list, length cap, short-circuit)
    ///   4. User dictionary block (if any)
    ///   5. Context + intensity guidelines
    ///   6. Optional preceding text
    ///   7. The transcript to process
    ///   8. Output contract
    ///
    /// The Chinese / English split mirrors the existing per-provider
    /// default system prompt in `AppGroupStore.defaultSystemPrompt(for:)`
    /// so the polish step stays in the user's chosen output language.
    internal func buildPrompt(for text: String, context: PolishContext) -> String {
        let dictionary = store.personalDictionary
        let dictionaryBlock = dictionary.promptFragment()
        let contextGuideline = context.appContext.polishGuideline
        let intensityGuideline = context.intensity.promptGuideline
        let precedingBlock = context.precedingForPrompt
            .map { "上文（仅供参考，**不要**改写）：\n\($0)\n" } ?? ""
        let useChinese = shouldUseChineseGuidance(providerId: store.providerId)

        if useChinese {
            return """
            你是智能语音输入法的后处理引擎。一次完成三件事：

            ## 任务 1：纠错
            - 修正明显的语音识别错误（同音字、近音字、漏字、错字）
            - 修正专有名词、英文术语（参考下面的用户词典）
            - **绝不**修改数字、人名、地名（除非明显错得离谱）

            ## 任务 2：润色
            - 删除冗余的语气词（嗯、呃、那个、就是、然后、对、ok）
            - 删除重复说错的字句
            - 必要时调整语序让表达更通顺
            - 加合适的标点

            ## 任务 3：风格适配
            当前输入场景：\(context.appContext.rawValue)
            风格要求：\(contextGuideline)
            润色档位：\(intensityGuideline)

            ## 重要规则
            1. **最小改动原则**：原文已经能听懂的部分不要重写
            2. 保留说话人的口吻和意图
            3. 不添加原文中没有的信息
            4. 短句（≤ 8 个中文字符 或 ≤ 15 个英文字符）直接原样返回，不要润色
            5. 输出语言必须与原文一致

            \(dictionaryBlock.isEmpty ? "" : "## 用户词典（必须原样保留，禁止改写）\n\(dictionaryBlock)\n")
            \(precedingBlock)
            ## 原文
            \(text)

            请直接输出处理后的文本，**不要任何解释**。
            """
        } else {
            return """
            You are the post-processing engine of a voice-input keyboard. Complete three tasks in one pass:

            ## Task 1: Correction
            - Fix obvious speech-recognition errors (homophones, near-misses, missing/extra characters).
            - Correct proper nouns, English terms, and technical identifiers (see the user dictionary below).
            - **Never** alter numbers, person names, or place names unless clearly wrong.

            ## Task 2: Polish
            - Remove redundant filler words (um, uh, like, you know, basically).
            - Remove duplicated fragments the speaker self-corrected.
            - Adjust obviously broken word order.
            - Add appropriate punctuation and capitalization.

            ## Task 3: Style adaptation
            Current input context: \(context.appContext.rawValue)
            Style guideline: \(contextGuideline)
            Polish intensity: \(intensityGuideline)

            ## Hard rules
            1. Minimum-change principle: do not rewrite parts the user already said clearly.
            2. Preserve the speaker's voice and intent.
            3. Never add information that is not in the original.
            4. Short inputs (≤ 15 English words or ≤ 8 CJK characters) must be returned verbatim.
            5. Output language must match the input language.

            \(dictionaryBlock.isEmpty ? "" : "## User dictionary (must be preserved verbatim)\n\(dictionaryBlock)\n")
            \(precedingBlock)
            ## Original transcript
            \(text)

            Output the processed text directly. **No explanation, no quotes, no preamble.**
            """
        }
    }

    /// Mirror `AppGroupStore.defaultSystemPrompt(for:)` — Chinese LLM
    /// providers get a Chinese prompt, English ones get English.
    /// Keeping these aligned avoids the "model answers in the wrong
    /// language" failure mode that LLM benchmarks consistently flag.
    private func shouldUseChineseGuidance(providerId: String) -> Bool {
        switch providerId {
        case "zhipu", "moonshot", "qwen", "deepseek":
            return true
        default:
            return false
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
