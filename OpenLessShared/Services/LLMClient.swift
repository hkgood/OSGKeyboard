// LLMClient.swift
// OSGKeyboard · Shared
//
// Protocol-based LLM client. Default implementation is the OpenAI-compatible
// chat completion client. Add other impls (Anthropic, Gemini) as needed.

import Foundation

public enum LLMError: Error, LocalizedError, Sendable {
    case invalidURL
    case noAPIKey
    case http(status: Int, body: String)
    case decoding(String)
    case transport(underlying: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidURL:                return "Invalid API URL."
        case .noAPIKey:                  return "API key is missing."
        case .http(let s, let body):
            return "API returned HTTP \(s): \(body.prefix(200))"
        case .decoding(let s):           return "Failed to decode response: \(s)"
        case .transport(let s):          return "Network error: \(s)"
        case .cancelled:                 return "Request was cancelled."
        }
    }
}

public protocol LLMClient: Sendable {
    func polish(_ text: String, systemPrompt: String) async throws -> String
}

// MARK: - OpenAI-compatible implementation

public struct OpenAICompatibleClient: LLMClient {
    public let baseURL: String
    public let apiKey: String
    public let model: String
    public let session: URLSession

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

    public func polish(_ text: String, systemPrompt: String) async throws -> String {
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
        req.timeoutInterval = 15

        let encoder = JSONEncoder()
        req.httpBody = try encoder.encode(request)

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport(underlying: "non-HTTP response")
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw LLMError.http(status: http.statusCode, body: body)
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
            throw LLMError.transport(underlying: String(describing: error))
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
}
