// ProviderModelService.swift
// OSGKeyboard · Shared
//
// Lightweight provider tools used by Settings to validate endpoints and fetch
// model ids without coupling the UI to each vendor's response shape.

import Foundation

public enum ProviderModelServiceError: Error, LocalizedError, Sendable {
    case invalidURL
    case missingAPIKey
    case http(Int)
    case empty
    case decoding
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return SharedL10n.string("providerTools.error.invalidURL")
        case .missingAPIKey:
            return SharedL10n.string("providerTools.error.missingAPIKey")
        case .http(let status):
            return SharedL10n.format("providerTools.error.http", status)
        case .empty:
            return SharedL10n.string("providerTools.error.empty")
        case .decoding:
            return SharedL10n.string("providerTools.error.decoding")
        case .transport:
            return SharedL10n.string("providerTools.error.transport")
        }
    }
}

public enum ProviderModelService {
    public static func listLLMModels(
        providerId: String,
        baseURL: String,
        apiKey: String,
        currentModel: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        if providerId == "anthropic" {
            return try await fetchModels(
                baseURL: "https://api.anthropic.com/v1",
                apiKey: apiKey,
                authorization: .anthropic,
                session: session
            )
        }
        return try await fetchModels(
            baseURL: resolvedLLMBaseURL(providerId: providerId, baseURL: baseURL),
            apiKey: apiKey,
            authorization: .bearer,
            session: session,
            fallback: currentModel
        )
    }

    public static func listASRModels(
        providerId: String,
        baseURL: String,
        apiKey: String,
        currentModel: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        switch CloudASRModelCatalog.strategy(for: providerId) {
        case .volcengineStreaming, .bailianStreaming:
            return singleModel(currentModel, fallback: CloudASRModelCatalog.defaultModel(for: providerId))
        case .localFallback:
            return []
        case .prompt, .openRouterJson, .zhipuHotwords:
            return try await fetchModels(
                baseURL: baseURL.isEmpty ? LLMProvider.provider(id: providerId).defaultBaseURL : baseURL,
                apiKey: apiKey,
                authorization: .bearer,
                session: session,
                fallback: currentModel
            )
        }
    }

    private enum Authorization {
        case bearer
        case anthropic
    }

    private static func fetchModels(
        baseURL: String,
        apiKey: String,
        authorization: Authorization,
        session: URLSession,
        fallback: String = ""
    ) async throws -> [String] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderModelServiceError.missingAPIKey
        }
        guard let url = URL(string: modelsEndpoint(baseURL: baseURL)) else {
            throw ProviderModelServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch authorization {
        case .bearer:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderModelServiceError.transport("non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ProviderModelServiceError.http(http.statusCode)
            }
            let models = try parseModels(from: data)
            let resolved = models.isEmpty ? singleModel(fallback, fallback: "") : models
            guard !resolved.isEmpty else { throw ProviderModelServiceError.empty }
            return resolved
        } catch let error as ProviderModelServiceError {
            throw error
        } catch {
            throw ProviderModelServiceError.transport(String(describing: error))
        }
    }

    private static func parseModels(from data: Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderModelServiceError.decoding
        }
        if let data = root["data"] as? [[String: Any]] {
            return normalize(data.compactMap { $0["id"] as? String ?? $0["name"] as? String })
        }
        if let models = root["models"] as? [[String: Any]] {
            return normalize(models.compactMap { $0["id"] as? String ?? $0["name"] as? String })
        }
        if let models = root["models"] as? [String] {
            return normalize(models)
        }
        return []
    }

    private static func normalize(_ models: [String]) -> [String] {
        var seen = Set<String>()
        return models
            .map { model in
                model
                    .replacingOccurrences(of: "models/", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
            .sorted()
    }

    private static func modelsEndpoint(baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("/models") { return trimmed }
        return trimmed.hasSuffix("/") ? "\(trimmed)models" : "\(trimmed)/models"
    }

    private static func resolvedLLMBaseURL(providerId: String, baseURL: String) -> String {
        if !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return baseURL }
        if providerId == "gemini" {
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        }
        return LLMProvider.provider(id: providerId).defaultBaseURL
    }

    private static func singleModel(_ model: String, fallback: String) -> [String] {
        let resolved = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallback
            : model
        return resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [resolved]
    }
}
