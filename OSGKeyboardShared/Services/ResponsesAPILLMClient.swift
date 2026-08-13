// ResponsesAPILLMClient.swift
// OSGKeyboard · Shared
//
// OpenAI-style Responses API client used by AI keyboard mode for
// DeepSeek / OpenAI / xAI server-side `web_search`.

import Foundation

public struct ResponsesAPILLMClient: LLMClient {
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let providerId: String
    public let reasoningEffort: String
    public let session: URLSession
    public let requestTimeout: TimeInterval = 15

    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        providerId: String,
        reasoningEffort: String = "medium",
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.providerId = providerId
        self.reasoningEffort = reasoningEffort
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
        let request = try makeResponsesRequest(
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
                    providerId: providerId,
                    statusCode: http.statusCode,
                    responseByteCount: data.count,
                    response: http
                )
                if http.statusCode == 429 { throw LLMError.rateLimited }
                throw LLMError.http(status: http.statusCode)
            }
            let text = try Self.parseOutputText(from: data)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw LLMError.decoding("empty responses output_text")
            }
            return trimmed
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
                    let request = try makeResponsesRequest(
                        messages: messages,
                        timeout: timeout,
                        options: options,
                        stream: true
                    )
                    for try await event in LLMStreamingSession.mapSSE(
                        session: session,
                        request: request,
                        providerId: providerId,
                        parse: LLMStreamDeltaParser.responsesOutputTextDelta(from:)
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

    private func makeResponsesRequest(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions,
        stream: Bool
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }
        guard let url = Self.responsesURL(from: baseURL) else { throw LLMError.invalidURL }

        let system = messages.first(where: { $0.role == "system" })?.content
        let input: [[String: Any]] = messages
            .filter { $0.role != "system" }
            .map { ["role": $0.role, "content": $0.content] }

        var body: [String: Any] = [
            "model": model,
            "input": input,
            "tools": [["type": "web_search"]],
            "tool_choice": "auto",
            "max_output_tokens": options.maxTokens ?? LLMRequest.outputTokenLimit(
                for: messages.map(\.content).joined(separator: "\n")
            ),
        ]
        if let system, !system.isEmpty {
            body["instructions"] = system
        }
        // Responses reasoning control (OpenAI / DeepSeek Responses).
        body["reasoning"] = ["effort": reasoningEffort]
        if stream {
            body["stream"] = true
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout ?? requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// `https://api.openai.com/v1` → `…/v1/responses`; strip trailing slash.
    static func responsesURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "\(trimmed)/responses")
    }

    static func parseOutputText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.decoding("responses json")
        }
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }
        // Aggregate message content parts when `output_text` is absent.
        guard let output = json["output"] as? [[String: Any]] else {
            throw LLMError.decoding("responses output")
        }
        var chunks: [String] = []
        for item in output {
            guard (item["type"] as? String) == "message",
                  let content = item["content"] as? [[String: Any]] else {
                continue
            }
            for part in content {
                let type = part["type"] as? String
                if type == "output_text" || type == "text",
                   let text = part["text"] as? String {
                    chunks.append(text)
                }
            }
        }
        let joined = chunks.joined()
        guard !joined.isEmpty else {
            throw LLMError.decoding("responses message text")
        }
        return joined
    }
}
