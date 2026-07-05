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

public protocol LLMClient: Sendable {
    /// Polish `text` with `systemPrompt`. `timeout` overrides the
    /// per-request HTTP timeout for this call; when `nil` the client's
    /// `requestTimeout` baseline is used. Long transcripts must pass a
    /// larger, length-scaled timeout so the HTTP request is not cut off
    /// mid-generation (see `PolishingService.effectiveTimeout`).
    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String

    /// Baseline upper bound for a single LLM HTTP round-trip when no
    /// per-request `timeout` is supplied.
    var requestTimeout: TimeInterval { get }
}

public extension LLMClient {
    /// Convenience overload that uses the baseline `requestTimeout`.
    func polish(_ text: String, systemPrompt: String) async throws -> String {
        try await polish(text, systemPrompt: systemPrompt, timeout: nil)
    }
}

// MARK: - OpenAI-compatible implementation

public struct OpenAICompatibleClient: LLMClient {
    public let baseURL: String
    public let apiKey: String
    public let model: String
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
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }

        let urlString = baseURL.hasSuffix("/")
            ? "\(baseURL)chat/completions"
            : "\(baseURL)/chat/completions"
        guard let url = URL(string: urlString) else { throw LLMError.invalidURL }

        let request = LLMRequest(
            model: model,
            messages: [
                .system(systemPrompt),
                .user(text)
            ],
            temperature: 0.3,
            maxTokens: nil
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // Per-request timeout scales with transcript length; fall back to
        // the baseline when the caller does not supply one.
        req.timeoutInterval = timeout ?? requestTimeout

        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport("non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                #if DEBUG
                // Log full body for debugging — never expose to UI.
                let body = String(data: data, encoding: .utf8) ?? ""
                print("⚠️ LLM HTTP \(http.statusCode): \(body.prefix(500))")
                #endif
                if http.statusCode == 429 { throw LLMError.rateLimited }
                throw LLMError.http(status: http.statusCode)
            }
            do {
                let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
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
}

// MARK: - Factory

public enum LLMClientFactory {
    /// Build a client from the current `ProviderConfig`.
    public static func make(from config: ProviderConfig) -> LLMClient {
        OpenAICompatibleClient(
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model
        )
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
