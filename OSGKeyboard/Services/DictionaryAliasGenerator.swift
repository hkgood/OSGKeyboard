// DictionaryAliasGenerator.swift
// OSGKeyboard · Main App
//
// After the user manually adds or edits a personal-dictionary term,
// asks the built-in DeepSeek endpoint for common ASR misrecognitions.
// Runs only in the main app (Settings) — the keyboard extension reads
// the persisted aliases on the next polish / correction call.

import Foundation
import OSGKeyboardShared

struct DictionaryAliasGenerator: Sendable {
    private let client: LLMClient?
    private let timeout: TimeInterval

    init(client: LLMClient? = nil, timeout: TimeInterval = 12) {
        self.client = client
        self.timeout = timeout
    }

    func generateAliases(for term: String) async -> [String] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        do {
            let client = try resolveClient()
            let prompt = Self.makePrompt(for: trimmed)
            let raw = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await client.polish(trimmed, systemPrompt: prompt)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            return Self.parseAliases(from: raw, excludingTerm: trimmed)
        } catch {
            #if DEBUG
            print("⚠️ [DictionaryAliasGenerator] alias generation failed: \(error)")
            #endif
            return []
        }
    }

    private func resolveClient() throws -> LLMClient {
        if let client {
            return client
        }
        guard PreconfiguredKeys.isDeepseekConfigured else {
            throw LLMError.noAPIKey
        }
        let preset = LLMProvider.provider(id: "deepseek")
        return OpenAICompatibleClient(
            baseURL: preset.defaultBaseURL,
            apiKey: PreconfiguredKeys.deepseek,
            model: preset.defaultModel
        )
    }

    private static func makePrompt(for term: String) -> String {
        """
        你是语音识别纠错助手。用户把专有词汇「\(term)」加入了个人词库。
        请列出该词在中文或英文语音输入时最常见的 3–6 个误识别写法（同音字、近音字、拼音混淆、英文误听等）。
        不要包含正确词「\(term)」本身。
        只输出 JSON 字符串数组，例如 ["误识别1","误识别2"]。若无合理别名则输出 []。
        """
    }

    static func parseAliases(from raw: String, excludingTerm term: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonSlice = extractJSONArray(from: trimmed) ?? trimmed
        guard let data = jsonSlice.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }

        let termLower = term.lowercased()
        var seen = Set<String>()
        var result: [String] = []
        for alias in decoded {
            let cleaned = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            let key = cleaned.lowercased()
            guard key != termLower, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
            if result.count >= 6 { break }
        }
        return result
    }

    private static func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end
        else { return nil }
        return String(text[start...end])
    }
}
