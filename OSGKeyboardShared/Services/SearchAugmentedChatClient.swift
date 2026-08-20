// SearchAugmentedChatClient.swift
// OSGKeyboard · Shared
//
// Chat Completions client that injects provider-specific web-search fields
// (Qwen `enable_search`, Zhipu `tools.web_search`, Moonshot `$web_search`).

import Foundation

/// Provider-specific Chat Completions extras for AI-mode web search.
/// Kept as an enum so the client stays `Sendable` (no `[String: Any]` storage).
public enum SearchBodyAugmentation: Sendable, Equatable {
    case qwenEnableSearch
    case zhipuWebSearch
    case moonshotBuiltinWebSearch

    func apply(to body: inout [String: Any]) {
        switch self {
        case .qwenEnableSearch:
            body["enable_search"] = true
        case .zhipuWebSearch:
            body["tools"] = [
                [
                    "type": "web_search",
                    "web_search": ["enable": true]
                ]
            ]
        case .moonshotBuiltinWebSearch:
            body["tools"] = [
                [
                    "type": "builtin_function",
                    "function": ["name": "$web_search"]
                ]
            ]
        }
    }
}

public struct SearchAugmentedChatClient: LLMClient {
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let providerId: String
    public let augmentation: SearchBodyAugmentation
    public let session: URLSession
    public let requestTimeout: TimeInterval = 15

    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        providerId: String,
        augmentation: SearchBodyAugmentation,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.providerId = providerId
        self.augmentation = augmentation
        self.session = session
    }

    public func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        try await complete(
            messages: [.system(systemPrompt), .user(text)],
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
            messages: [.system(systemPrompt), .user(text)],
            timeout: timeout,
            options: options
        )
    }

    public func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        let req = try makeSearchChatRequest(
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
            let decoded = try JSONDecoder().decode(LLMResponse.self, from: data)
            return decoded.content.trimmingCharacters(in: .whitespacesAndNewlines)
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
                    let req = try makeSearchChatRequest(
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

    private func makeSearchChatRequest(
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
            thinkingEnabled: true
        )
        let request = LLMRequest(
            model: model,
            messages: messages,
            temperature: omitSampling ? nil : options.temperature,
            maxTokens: options.maxTokens ?? LLMRequest.outputTokenLimit(
                for: messages.map(\.content).joined(separator: "\n")
            ),
            topP: omitSampling ? nil : options.topP
        )

        let encoded = try JSONEncoder().encode(request)
        guard var body = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw LLMError.decoding("chat body")
        }
        LLMThinkingControl.apply(
            to: &body,
            providerId: providerId,
            baseURL: baseURL,
            model: model,
            enabled: true
        )
        augmentation.apply(to: &body)
        if stream {
            body["stream"] = true
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = timeout ?? requestTimeout
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}
