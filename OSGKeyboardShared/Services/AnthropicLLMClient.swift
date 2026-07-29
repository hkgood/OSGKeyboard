// AnthropicLLMClient.swift
// OSGKeyboard · Shared
//
// Anthropic Messages API client for polish / translation prompts.

import Foundation

public struct AnthropicMessagesClient: LLMClient {
    public let apiKey: String
    public let model: String
    public let session: URLSession
    public let requestTimeout: TimeInterval = 15

    public init(
        apiKey: String,
        model: String,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
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
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var body: [String: Any] = [
            "model": model,
            "max_tokens": options.maxTokens ?? LLMRequest.outputTokenLimit(for: text),
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": text],
            ],
        ]
        if let temperature = options.temperature {
            body["temperature"] = temperature
        }
        if let topP = options.topP {
            body["top_p"] = topP
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeout ?? requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport("non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                if http.statusCode == 429 { throw LLMError.rateLimited }
                throw LLMError.http(status: http.statusCode)
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let first = content.first,
                  let textBlock = first["text"] as? String else {
                throw LLMError.decoding("anthropic content")
            }
            let usage = json["usage"] as? [String: Any]
            LLMCacheMetricsStore.record(
                providerId: "anthropic",
                promptTokens: usage?["input_tokens"] as? Int,
                cachedTokens: usage?["cache_read_input_tokens"] as? Int
            )
            return textBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let err as LLMError {
            throw err
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch {
            throw LLMError.transport(String(describing: error))
        }
    }
}
