// LLMCacheMetricsStore.swift
// OSGKeyboard · Shared
//
// Small App Group diagnostic snapshot for validating provider prompt caching.

import Foundation

public struct LLMCacheMetrics: Codable, Equatable, Sendable {
    public let providerId: String
    public let promptTokens: Int?
    public let cachedTokens: Int?
    public let observedAt: TimeInterval

    public var summary: String {
        guard let cachedTokens else { return "n/a (\(providerId))" }
        guard let promptTokens, promptTokens > 0 else {
            return "\(cachedTokens) cached (\(providerId))"
        }
        let rate = Int((Double(cachedTokens) / Double(promptTokens) * 100).rounded())
        return "\(cachedTokens)/\(promptTokens) \(rate)% (\(providerId))"
    }
}

public enum LLMCacheMetricsStore {
    private static let key = "debug.llmCacheMetrics.v1"

    public static func record(
        providerId: String,
        promptTokens: Int?,
        cachedTokens: Int?,
        defaults: UserDefaults? = nil
    ) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        let metrics = LLMCacheMetrics(
            providerId: providerId.isEmpty ? "openai-compatible" : providerId,
            promptTokens: promptTokens,
            cachedTokens: cachedTokens,
            observedAt: Date().timeIntervalSince1970
        )
        guard let data = try? JSONEncoder().encode(metrics) else { return }
        store.set(data, forKey: key)
    }

    public static func latest(defaults: UserDefaults? = nil) -> LLMCacheMetrics? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable,
              let data = store.data(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(LLMCacheMetrics.self, from: data)
    }
}
