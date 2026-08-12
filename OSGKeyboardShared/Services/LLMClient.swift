// LLMClient.swift
// OSGKeyboard · Shared
//
// Protocol-based LLM client. Default implementation is the OpenAI-compatible
// chat completion client. Add other impls (Anthropic, Gemini) as needed.

import Foundation

public enum LLMError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case noAPIKey
    case http(status: Int)
    case decoding(String)
    case transport(String)
    case cancelled
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return SharedL10n.string("error.llm.invalidURL")
        case .noAPIKey:
            return SharedL10n.string("error.llm.noAPIKey")
        case .http(let status):
            return SharedL10n.format("error.llm.http", status)
        case .decoding:
            return SharedL10n.string("error.llm.decoding")
        case .transport:
            return SharedL10n.string("error.llm.transport")
        case .rateLimited:
            return SharedL10n.string("error.llm.rateLimited")
        case .cancelled:
            return SharedL10n.string("error.llm.cancelled")
        }
    }
}

enum LLMHTTPDiagnostics {
    static func logFailure(
        providerId: String,
        statusCode: Int,
        responseByteCount: Int,
        response: HTTPURLResponse
    ) {
        #if DEBUG
        let provider = safeToken(providerId) ?? "unknown"
        let requestID = [
            "x-request-id",
            "request-id",
            "x-correlation-id",
            "cf-ray",
        ]
        .compactMap { response.value(forHTTPHeaderField: $0) }
        .compactMap(safeToken)
        .first
        let requestMetadata = requestID.map { " requestId=\($0)" } ?? ""
        print(
            "⚠️ LLM HTTP error provider=\(provider) status=\(statusCode) "
                + "responseBytes=\(responseByteCount)\(requestMetadata)"
        )
        #endif
    }

    private static func safeToken(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:"))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return trimmed
    }
}

public struct LLMGenerationOptions: Sendable, Equatable {
    public let temperature: Double?
    public let topP: Double?
    public let maxTokens: Int?

    public init(temperature: Double? = 0.1, topP: Double? = 0.9, maxTokens: Int? = nil) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
    }

    public static let polishDefault = LLMGenerationOptions()
    public static let funCreative = LLMGenerationOptions(
        temperature: 0.65,
        topP: 0.9
    )
}

public protocol LLMClient: Sendable {
    /// Polish `text` with `systemPrompt`. `timeout` overrides the
    /// per-request HTTP timeout for this call; when `nil` the client's
    /// `requestTimeout` baseline is used. Long transcripts must pass a
    /// larger, length-scaled timeout so the HTTP request is not cut off
    /// mid-generation (see `PolishingService.effectiveTimeout`).
    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String

    /// Provider clients override this to support per-attempt generation controls.
    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String

    /// Complete an explicit chat transcript. AI question mode uses this path;
    /// dictation polish keeps the narrower `polish` API above.
    func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String

    /// Stream visible answer deltas for AI keyboard mode. Default falls back to
    /// a single delta from `complete`. Reasoning / tool scaffolding must not be
    /// yielded as answer text.
    func completeStreaming(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error>

    /// Baseline upper bound for a single LLM HTTP round-trip when no
    /// per-request `timeout` is supplied.
    var requestTimeout: TimeInterval { get }
}

public extension LLMClient {
    /// Convenience overload that uses the baseline `requestTimeout`.
    func polish(_ text: String, systemPrompt: String) async throws -> String {
        try await polish(text, systemPrompt: systemPrompt, timeout: nil)
    }

    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        try await polish(text, systemPrompt: systemPrompt, timeout: timeout)
    }

    /// Compatibility fallback for injected polish-only clients. Production
    /// provider clients override this method to preserve all conversation turns.
    func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        let systemPrompt = messages.first(where: { $0.role == "system" })?.content ?? ""
        let userText = messages.last(where: { $0.role == "user" })?.content ?? ""
        return try await polish(
            userText,
            systemPrompt: systemPrompt,
            timeout: timeout,
            options: options
        )
    }

    /// Non-streaming fallback used by test doubles and polish-only clients.
    func completeStreaming(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let text = try await complete(
                        messages: messages,
                        timeout: timeout,
                        options: options
                    )
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        continuation.yield(.delta(trimmed))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - OpenAI-compatible implementation

public struct OpenAICompatibleClient: LLMClient {
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let providerId: String
    public let thinkingEnabled: Bool
    public let session: URLSession

    /// Canonical request timeout for a single LLM HTTP round-trip. Both
    /// the `URLRequest.timeoutInterval` we set below and any external
    /// race that wants to bound the total time spent waiting on the LLM
    /// (e.g. `PolishingService`) should derive from this constant.
    public let requestTimeout: TimeInterval = 15

    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        providerId: String = "",
        thinkingEnabled: Bool = false,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.providerId = providerId
        self.thinkingEnabled = thinkingEnabled
        self.session = session
    }

    public func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        try await polish(
            text,
            systemPrompt: systemPrompt,
            timeout: timeout,
            options: .polishDefault
        )
    }

    public func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        try await complete(
            messages: [
                .system(systemPrompt),
                .user(text),
            ],
            timeout: timeout,
            options: options
        )
    }

    public func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        let req = try makeChatRequest(
            messages: messages,
            timeout: timeout,
            options: options,
            stream: false
        )

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport("non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                LLMHTTPDiagnostics.logFailure(
                    providerId: providerId,
                    statusCode: http.statusCode,
                    responseByteCount: data.count,
                    response: http
                )
                if http.statusCode == 429 { throw LLMError.rateLimited }
                throw LLMError.http(status: http.statusCode)
            }
            do {
                let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
                LLMCacheMetricsStore.record(
                    providerId: providerId,
                    promptTokens: decoded.usage?.promptTokens,
                    cachedTokens: decoded.usage?.cachedTokens
                )
                return decoded.content.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw LLMError.decoding(String(describing: error))
            }
        } catch let err as LLMError {
            throw err
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw LLMError.cancelled
        } catch {
            throw LLMError.transport(String(describing: error))
        }
    }

    public func completeStreaming(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try makeChatRequest(
                        messages: messages,
                        timeout: timeout,
                        options: options,
                        stream: true
                    )
                    for try await event in LLMStreamingSession.mapSSE(
                        session: session,
                        request: req,
                        providerId: providerId,
                        parse: LLMStreamDeltaParser.chatCompletionsDelta(from:)
                    ) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMError.transport(String(describing: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeChatRequest(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions,
        stream: Bool
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }

        let urlString = baseURL.hasSuffix("/")
            ? "\(baseURL)chat/completions"
            : "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else { throw LLMError.invalidURL }

        let omitSampling = LLMThinkingControl.shouldOmitSamplingParameters(
            providerId: providerId,
            baseURL: baseURL,
            model: model,
            thinkingEnabled: thinkingEnabled
        )
        let request = LLMRequest(
            model: model,
            messages: messages,
            temperature: omitSampling ? nil : options.temperature,
            maxTokens: options.maxTokens ?? Self.outputTokenLimit(for: messages),
            topP: omitSampling ? nil : options.topP
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Per-request timeout scales with transcript length; fall back to
        // the baseline when the caller does not supply one.
        req.timeoutInterval = timeout ?? requestTimeout
        req.httpBody = try Self.encodedBody(
            request,
            providerId: providerId,
            baseURL: baseURL,
            model: model,
            thinkingEnabled: thinkingEnabled,
            stream: stream
        )
        return req
    }

    private static func outputTokenLimit(
        for messages: [LLMRequest.Message]
    ) -> Int {
        let combined = messages.map(\.content).joined(separator: "\n")
        return LLMRequest.outputTokenLimit(for: combined)
    }

    private static func encodedBody(
        _ request: LLMRequest,
        providerId: String,
        baseURL: String,
        model: String,
        thinkingEnabled: Bool,
        stream: Bool = false
    ) throws -> Data {
        let encoded = try JSONEncoder().encode(request)
        guard var body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return encoded
        }
        LLMThinkingControl.apply(
            to: &body,
            providerId: providerId,
            baseURL: baseURL,
            model: model,
            enabled: thinkingEnabled
        )
        if stream {
            body["stream"] = true
        }
        return try JSONSerialization.data(withJSONObject: body)
    }
}

// MARK: - Factory

public enum LLMClientFactory {
    /// Build a client from the current `ProviderConfig`.
    public static func make(from config: ProviderConfig) -> LLMClient {
        make(
            providerId: config.providerId,
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model,
            thinkingEnabled: config.llmThinkingEnabled
        )
    }

    /// Provider-aware factory used by `PolishingService`.
    public static func make(
        providerId: String,
        baseURL: String,
        apiKey: String,
        model: String,
        thinkingEnabled: Bool = false,
        session: URLSession = .shared
    ) -> LLMClient {
        switch providerId {
        case "anthropic":
            return AnthropicMessagesClient(apiKey: apiKey, model: model, session: session)
        default:
            let resolvedBase = resolvedOpenAICompatibleBaseURL(providerId: providerId, baseURL: baseURL)
            return OpenAICompatibleClient(
                baseURL: resolvedBase,
                apiKey: apiKey,
                model: model,
                providerId: providerId,
                thinkingEnabled: thinkingEnabled,
                session: session
            )
        }
    }

    /// Gemini exposes an OpenAI-compatible shim under `/v1beta/openai`.
    private static func resolvedOpenAICompatibleBaseURL(providerId: String, baseURL: String) -> String {
        if !baseURL.isEmpty { return baseURL }
        switch providerId {
        case "gemini":
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        default:
            return baseURL
        }
    }

    /// Single source of truth for the LLM request timeout, shared by
    /// `LLMClient.requestTimeout` implementations and any caller that
    /// wants to bound total time spent waiting on the LLM (e.g.
    /// `PolishingService`'s safety-net `withThrowingTaskGroup`). Use
    /// this instead of hard-coding `15` so all timeouts stay aligned.
    public static var defaultRequestTimeout: TimeInterval {
        OpenAICompatibleClient(baseURL: "", apiKey: "", model: "").requestTimeout
    }
}

// MARK: - Provider-specific thinking controls
//
// Cloud polish defaults to thinking OFF (`llmThinkingEnabled == false`).
// DeepSeek V4 thinking defaults to *enabled* server-side, so we must send an
// explicit `thinking: { type: "disabled" }` — merely omitting the field (or
// sending `reasoning_effort: "low"`, which DeepSeek maps to `high`) leaves
// CoT on and makes polish appear stuck.

enum LLMThinkingControl {
    static func shouldOmitSamplingParameters(
        providerId: String,
        baseURL: String,
        model: String,
        thinkingEnabled: Bool
    ) -> Bool {
        if thinkingEnabled { return true }
        return control(providerId: providerId, baseURL: baseURL, model: model) == .openAIReasoning
    }

    static func apply(
        to body: inout [String: Any],
        providerId: String,
        baseURL: String,
        model: String,
        enabled: Bool
    ) {
        switch control(providerId: providerId, baseURL: baseURL, model: model) {
        case .deepSeek:
            // Official toggle; do not send reasoning_effort when disabled —
            // DeepSeek maps low/medium → high while thinking stays on.
            body["thinking"] = ["type": enabled ? "enabled" : "disabled"]
            if enabled {
                body["reasoning_effort"] = "high"
            } else {
                body.removeValue(forKey: "reasoning_effort")
            }
        case .miniMax:
            body["thinking"] = ["type": enabled ? "adaptive" : "disabled"]
        case .gemini:
            body["thinking_config"] = [
                "thinking_budget": enabled ? -1 : 0
            ]
        case .openAIReasoning:
            // o-series / gpt-5: only touch the field when the user opts in,
            // or when disabling an always-on reasoner with the lowest effort.
            if enabled {
                body["reasoning_effort"] = "medium"
            } else {
                body["reasoning_effort"] = "low"
            }
        case .none:
            return
        }
    }

    private enum Control {
        /// DeepSeek / Ark: explicit thinking type toggle.
        case deepSeek
        case miniMax
        case gemini
        case openAIReasoning
    }

    private static func control(
        providerId: String,
        baseURL: String,
        model: String
    ) -> Control? {
        switch providerId {
        case "deepseek", "ark":
            return .deepSeek
        case "minimax":
            return .miniMax
        case "gemini":
            return .gemini
        case "openai":
            return isOpenAIReasoningModel(model) ? .openAIReasoning : nil
        default:
            return control(baseURL: baseURL, model: model)
        }
    }

    private static func control(baseURL: String, model: String) -> Control? {
        let lower = baseURL.lowercased()
        if lower.contains("minimax") || lower.contains("minimaxi") {
            return .miniMax
        }
        if lower.contains("generativelanguage.googleapis.com") {
            return .gemini
        }
        // Hosted DeepSeek (SiliconFlow / OpenRouter / custom proxies).
        if lower.contains("deepseek") || model.lowercased().contains("deepseek") {
            return .deepSeek
        }
        return nil
    }

    private static func isOpenAIReasoningModel(_ model: String) -> Bool {
        let lower = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("o1")
            || lower.hasPrefix("o3")
            || lower.hasPrefix("o4")
            || lower.hasPrefix("gpt-5")
            || lower.contains("reasoning")
    }
}
