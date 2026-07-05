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
//   - `engineMode == "cloud"`  → on-device ASR, then user's cloud LLM
//   - `engineMode == "local"`  → on-device ASR, then built-in DeepSeek
//   - Ultra-short, structure-free utterances skip the LLM entirely
//   - Cloud without API key     → raw + `.missingAPIKey` warning
//   - Local without build key   → raw + `.missingAPIKey` warning
//
// Caller-supplied `PolishContext` carries the per-call signals:
//   - `appContext`     code / email / chat / document / unknown
//   - `intensity`      light / medium / heavy (per-call override)
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

    /// `timeout` is the baseline (shortest) per-request HTTP timeout,
    /// used as the floor for `effectiveTimeout(for:)`. It defaults to the
    /// shared `LLMClient.requestTimeout`. The safety-net timer adds its
    /// own slack on top of the length-scaled budget in `polishRemote`, so
    /// no `+1` is baked in here.
    public init(
        store: AppGroupStore = AppGroupStore(),
        client: LLMClient? = nil,
        timeout: TimeInterval? = nil
    ) {
        self.store = store
        self.injectedClient = client
        self.timeout = timeout ?? LLMClientFactory.defaultRequestTimeout
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

        let resolvedContext = resolveContext(override: context)

        // Ultra-short, structure-free inputs skip the LLM to save
        // latency (e.g. "好", "OK", "明天见").
        if mode == .polish,
           systemPrompt == nil || systemPrompt?.isEmpty == true,
           TranscriptPostProcessor.shouldSkipLLM(for: trimmed) {
            return TranscriptPostProcessor.localClean(trimmed)
        }

        if store.engineMode == "cloud", injectedClient == nil {
            guard !store.apiKey.isEmpty else {
                throw PolishError.missingAPIKey
            }
        }

        let llmResult = try await polishRemote(
            trimmed,
            mode: mode,
            systemPrompt: systemPrompt,
            providerIdOverride: providerIdOverride,
            context: resolvedContext
        )

        // Translation and custom prompts bypass the polish post-processor.
        if mode != .polish || (systemPrompt != nil && !(systemPrompt?.isEmpty ?? true)) {
            return llmResult
        }

        return TranscriptPostProcessor.process(original: trimmed, llmOutput: llmResult)
    }

    private func resolveContext(override: PolishContext?) -> PolishContext {
        guard let override else {
            return PolishContext(
                appContext: store.detectedAppContext?.context ?? .unknown,
                intensity: store.polishIntensity
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
    ) async throws -> String {
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
            let apiKey: String
            if effectiveProviderId == "deepseek" {
                guard PreconfiguredKeys.isDeepseekConfigured else {
                    throw PolishError.missingAPIKey
                }
                apiKey = PreconfiguredKeys.deepseek
            } else {
                apiKey = store.apiKey
            }
            client = OpenAICompatibleClient(baseURL: baseURL, apiKey: apiKey, model: model)
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
                    appContext: context.appContext
                )
            }
        }
        let budget = effectiveTimeout(for: trimmed)
        // The HTTP request itself uses `budget`; the safety-net timer is
        // given a small slack on top so a clean URL timeout surfaces its
        // (more specific) transport error before the race fires.
        let safetyNet = budget + 2

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await client.polish(trimmed, systemPrompt: prompt, timeout: budget)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(safetyNet * 1_000_000_000))
                throw PolishError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Shared output contract injected into every polish prompt.
    internal static func globalOutputContract(useChinese: Bool) -> String {
        if useChinese {
            return """
            ## 全局输出契约（所有润色档位均必须遵守，优先级最高）
            1. **禁止新增 emoji**：原文无 emoji 时输出不得出现 emoji；原文有 emoji 时仅可原样保留。
            2. **必须恢复合理标点**：逗号、句号、问号、感叹号；按语义分句，不要输出无标点长段。
            3. **必须做内容触发型结构化**（所有档位）：
               - 「第一点/第二个/步骤一/一是二是三是」→ 转为 `1. ` 编号列表并换行
               - 「首先/其次/最后/另外/一方面」→ 分段换行，不强行编号
               - 待办、会议纪要、多个问题、长文本多句 → 按语义分段
               - 短但含结构信号的文本仍要格式化；极短且无结构的已由系统跳过
            4. **数字要结合上下文判断**（重要）：
               - 有意义的数字（价格、日期、数量、时间、电话、版本号）→ 保持不变
               - 但语音里的序号常被误识别成数字或时间，需结合上下文修回并列表化：
                 · 已出现「第一点」，随后的「第2:00 / 第2点0 / 第二零零」多半是「第二点」，「第3:00」多半是「第三点」
                 · 「1、2、3」「一、二、三」在列举语境里就是序号，转成 `1. ` 列表
               - 判断依据是上下文里是否在“分点/列举”，不要机械地保留听错的数字
            5. **保守改写**：能加标点就不改词；能分段就不重写；能小改就不大改；不新增事实。
            6. **不改**人名、地名、专有名词（除非 ASR 明显错误）。
            7. 输出语言必须与原文一致；不翻译、不扩写成 AI 文案。
            8. 只输出最终文本：不要解释、不要引号包裹、不要前缀说明。
            """
        } else {
            return """
            ## Global output contract (mandatory at every intensity — highest priority)
            1. **No new emojis**: if the original has none, output must have none; preserve originals only.
            2. **Restore proper punctuation**: commas, periods, question marks; break run-on speech into sentences.
            3. **Content-triggered structure** (every intensity):
               - "first point / second / step one / one is two is three" → numbered `1. ` list with line breaks
               - "firstly / secondly / finally / on the other hand" → paragraph breaks, not forced numbering
               - todos, meeting notes, multiple questions, long multi-clause speech → semantic paragraphs
            4. **Judge numbers by context** (important):
               - Meaningful numbers (prices, dates, quantities, times, phone numbers, versions) → keep unchanged.
               - But spoken ordinals are often misrecognized as digits/times; use context to restore and listify:
                 · after a "first point", a following "2:00 / point 2 / two oh oh" is likely "second point", "3:00" is "third point"
                 · "1, 2, 3" or "one, two, three" in an enumerating context are ordinals → convert to a `1. ` list
               - Decide by whether the context is enumerating; do not mechanically preserve a misheard number.
            5. **Conservative rewrite**: prefer punctuation over rewording; prefer breaks over rewriting; minimal changes.
            6. **Do not** alter person names, places, or proper nouns unless clearly misrecognized.
            7. Output language must match the input; do not translate or expand into marketing copy.
            8. Output the final text only: no explanation, no quotes, no preamble.
            """
        }
    }

    internal func buildPrompt(
        for text: String,
        context: PolishContext,
        providerId: String
    ) -> String {
        let dictionary = store.personalDictionary
        let dictionaryBlock = dictionary.promptFragment()
        let contextGuideline = context.appContext.polishGuideline
        let intensityGuideline = context.intensity.promptGuideline
        let contract = Self.globalOutputContract(useChinese: shouldUseChineseGuidance(providerId: providerId))
        let precedingBlock = context.precedingForPrompt
            .map {
                """
                ## 上文（仅供参考 — 用于术语/语气/是否续接列表或换行；**禁止**改写上文，**禁止**从上文新增事实）
                \($0)

                """
            } ?? ""
        let useChinese = shouldUseChineseGuidance(providerId: providerId)

        if useChinese {
            return """
            你是智能语音输入法的后处理引擎。一次完成：ASR 纠错、标点恢复、语义分段、按档位润色。

            \(contract)

            ## 任务 1：纠错
            - 修正明显的语音识别错误（同音字、近音字、漏字、错字）
            - 修正专有名词、英文术语（参考下面的用户词典）

            ## 任务 2：标点与结构
            - 恢复合理标点与句子边界
            - 识别口语中的列表、步骤、分点、会议纪要结构并格式化
            - 长文本按语义换行分段

            ## 任务 3：润色（按档位）
            当前输入场景：\(context.appContext.rawValue)
            风格要求：\(contextGuideline)
            润色档位：\(intensityGuideline)

            \(dictionaryBlock.isEmpty ? "" : "## 用户词典（必须原样保留，禁止改写）\n\(dictionaryBlock)\n")
            \(precedingBlock)## 原文
            \(text)

            请直接输出处理后的文本，**不要任何解释**。
            """
        } else {
            return """
            You are the post-processing engine of a voice-input keyboard. In one pass: fix ASR errors, restore punctuation, structure content, and polish per intensity.

            \(contract)

            ## Task 1: Correction
            - Fix obvious speech-recognition errors (homophones, near-misses, missing/extra characters).
            - Correct proper nouns, English terms, and technical identifiers (see the user dictionary below).

            ## Task 2: Punctuation and structure
            - Restore proper punctuation and sentence boundaries.
            - Detect oral lists, steps, enumerated points, meeting-note structure and format them.
            - Break long speech into semantic paragraphs.

            ## Task 3: Polish (per intensity)
            Current input context: \(context.appContext.rawValue)
            Style guideline: \(contextGuideline)
            Polish intensity: \(intensityGuideline)

            \(dictionaryBlock.isEmpty ? "" : "## User dictionary (must be preserved verbatim)\n\(dictionaryBlock)\n")
            \(precedingBlock)## Original transcript
            \(text)

            Output the processed text directly. **No explanation, no quotes, no preamble.**
            """
        }
    }

    private func shouldUseChineseGuidance(providerId: String) -> Bool {
        switch providerId {
        case "zhipu", "moonshot", "qwen", "deepseek":
            return true
        default:
            return false
        }
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
        let scaled = timeout + (Double(text.count) / 100.0) * 10.0
        return min(max(scaled, timeout), 120)
    }

    internal static func resolvedProviderId(
        store: AppGroupStore,
        providerIdOverride: String?
    ) -> String {
        if let providerIdOverride {
            return providerIdOverride
        }
        if store.engineMode == "local" {
            return "deepseek"
        }
        let id = store.providerId
        return id == "deepseek" ? "openai" : id
    }

    internal static func resolveLLMEndpoint(
        store: AppGroupStore,
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
            return "Missing API key (cloud: Settings API key; local: build configuration)."
        }
    }
}
