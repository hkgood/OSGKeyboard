// AnthropicLLMClient.swift
// OSGKeyboard · Shared
//
// Anthropic Messages API client for polish / translation / AI-mode prompts.

import Foundation

public struct AnthropicMessagesClient: LLMClient {
    public let apiKey: String
    public let model: String
    public let session: URLSession
    public let webSearchEnabled: Bool
    public let thinkingEnabled: Bool
    public let requestTimeout: TimeInterval = 15

    public init(
        apiKey: String,
        model: String,
        session: URLSession = .shared,
        webSearchEnabled: Bool = false,
        thinkingEnabled: Bool = false
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.webSearchEnabled = webSearchEnabled
        self.thinkingEnabled = thinkingEnabled
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
                .user(text)
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
        let request = try makeMessagesRequest(
            messages: messages,
            timeout: timeout,
            options: options,
            stream: false
        )

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport("non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                LLMHTTPDiagnostics.logFailure(
                    providerId: "anthropic",
                    statusCode: http.statusCode,
                    responseByteCount: data.count,
                    response: http
                )
                if http.statusCode == 429 { throw LLMError.rateLimited }
                throw LLMError.http(status: http.statusCode)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]] else {
                throw LLMError.decoding("anthropic content")
            }
            let textBlocks = content.compactMap { block -> String? in
                guard (block["type"] as? String) == "text",
                      let text = block["text"] as? String else {
                    return nil
                }
                return text
            }
            let joined = textBlocks.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !joined.isEmpty else {
                throw LLMError.decoding("anthropic text")
            }
            let usage = json["usage"] as? [String: Any]
            LLMCacheMetricsStore.record(
                providerId: "anthropic",
                promptTokens: usage?["input_tokens"] as? Int,
                cachedTokens: usage?["cache_read_input_tokens"] as? Int
            )
            return joined
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
                    let request = try makeMessagesRequest(
                        messages: messages,
                        timeout: timeout,
                        options: options,
                        stream: true
                    )
                    for try await event in LLMStreamingSession.mapSSE(
                        session: session,
                        request: request,
                        providerId: "anthropic",
                        parse: LLMStreamDeltaParser.anthropicTextDelta(from:)
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

    private func makeMessagesRequest(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions,
        stream: Bool
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let systemPrompt = messages.first(where: { $0.role == "system" })?.content ?? ""
        let conversation = messages
            .filter { $0.role != "system" }
            .map { ["role": $0.role, "content": $0.content] }
        let combinedText = messages.map(\.content).joined(separator: "\n")
        let answerTokens = options.maxTokens ?? LLMRequest.outputTokenLimit(for: combinedText)
        let thinkingBudget = 4_000
        var body: [String: Any] = [
            "model": model,
            // Anthropic requires max_tokens > thinking.budget_tokens.
            "max_tokens": thinkingEnabled ? answerTokens + thinkingBudget : answerTokens,
            "system": systemPrompt,
            "messages": conversation
        ]
        if thinkingEnabled {
            // Extended thinking; sampling knobs are ignored while thinking runs.
            body["thinking"] = [
                "type": "enabled",
                "budget_tokens": thinkingBudget
            ]
        } else {
            if let temperature = options.temperature {
                body["temperature"] = temperature
            }
            if let topP = options.topP {
                body["top_p"] = topP
            }
        }
        if webSearchEnabled {
            // Basic server-side search; newer tool revisions also work when the account allows.
            body["tools"] = [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 3
                ]
            ]
        }
        if stream {
            body["stream"] = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeout ?? requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
