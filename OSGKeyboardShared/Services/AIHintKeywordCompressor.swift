// AIHintKeywordCompressor.swift
// OSGKeyboard · Shared
//
// Optional LLM pass after deterministic keyword extraction. Failure leaves
// the extracted labels in place (hard truncate only as a last resort).

import Foundation

public struct AIHintKeywordCompressor: Sendable {
    private let client: LLMClient?
    private let timeout: TimeInterval

    public init(client: LLMClient? = nil, timeout: TimeInterval = 45) {
        self.client = client
        self.timeout = timeout
    }

    public func compress(
        cards: [AIHintCard],
        locale: String
    ) async -> [AIHintCard] {
        let prepared = cards.map { card -> AIHintCard in
            var copy = card
            copy.displayText = AIHintKeywordExtractor.displayText(for: card)
            return copy
        }
        let candidates = zip(cards, prepared).compactMap { original, extracted -> AIHintCard? in
            shouldCompress(extracted) ? original : nil
        }
        guard !candidates.isEmpty else { return prepared }

        do {
            let client = try resolveClient()
            let payload = candidates.map {
                [
                    "id": $0.id,
                    "text": $0.displayText,
                    "title": $0.metadata?.title ?? "",
                    "category": $0.category,
                    "source": $0.source,
                ]
            }
            let json = try JSONSerialization.data(withJSONObject: payload)
            let jsonText = String(data: json, encoding: .utf8) ?? "[]"
            let system = Self.systemPrompt(locale: locale)
            let raw = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await client.polish(jsonText, systemPrompt: system)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw CancellationError()
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            let mapping = Self.parseDisplayMap(from: raw)
            guard !mapping.isEmpty else { return prepared }
            return prepared.map { card in
                guard let display = mapping[card.id], !display.isEmpty else { return card }
                var copy = card
                copy.displayText = AIHintKeywordExtractor.finalize(display, locale: locale)
                return copy
            }
        } catch {
            #if DEBUG
            print("⚠️ [AIHintKeywordCompressor] failed: \(error)")
            #endif
            return prepared
        }
    }

    private func shouldCompress(_ card: AIHintCard) -> Bool {
        if isHistoricalToday(card) { return false }
        if card.requiresClipboard30s { return false }
        let limit = AIHintKeywordExtractor.characterLimit(locale: card.locale)
        return card.displayText.count > limit
            || card.displayText.contains("…")
    }

    private func isHistoricalToday(_ card: AIHintCard) -> Bool {
        let haystack = card.displayText + card.prompt
        return haystack.contains("历史上的今天")
            || haystack.localizedCaseInsensitiveContains("on this day")
    }

    private func resolveClient() throws -> LLMClient {
        if let client { return client }
        let store = AppGroupStore()
        let apiKey = store.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw LLMError.noAPIKey }
        let providerId = store.providerId
        let preset = LLMProvider.provider(id: providerId)
        let baseURL = store.baseURL.isEmpty ? preset.defaultBaseURL : store.baseURL
        let model = store.model.isEmpty ? preset.defaultModel : store.model
        return LLMClientFactory.make(
            providerId: providerId,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            thinkingEnabled: store.llmThinkingEnabled
        )
    }

    private static func systemPrompt(locale: String) -> String {
        if locale == "zh" {
            return """
            你是输入法 AI 空闲轮播的关键词提取器。
            输入是 JSON 数组，每项含 id/text/title/category/source。
            输出 JSON 数组，每项仅 {"id","displayText"}。

            硬性规则：
            - displayText 必须是实体/关键词，不要写成问句或动作句
            - 禁止「聊聊」「看看」「帮我」等动词前缀
            - 单行，不要省略号结尾
            - 中文约 4–10 字；优先用 title 字段
            - 丢弃「历史上的今天」类条目（不要输出它们的 id）
            - 不要改写 prompt；不要 Markdown；只输出 JSON
            """
        }
        return """
        You extract keywords for AI keyboard idle hint chips.
        Input: JSON array of {id,text,title,category,source}.
        Output: JSON array of {"id","displayText"} only.

        Rules:
        - displayText is the entity/keyword, not a question or action sentence
        - No "Chat"/"Chat about" prefix
        - One line, no trailing ellipsis
        - English: ≤22 characters; prefer the title field
        - Drop "On this day" / historical-today items (omit their ids)
        - Do not change prompts; JSON only, no Markdown
        """
    }

    public static func parseDisplayMap(from raw: String) -> [String: String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slice = extractJSONArray(from: trimmed) ?? Optional(trimmed),
              let data = slice.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }

        var map: [String: String] = [:]
        for row in rows {
            guard let id = row["id"] as? String,
                  let display = row["displayText"] as? String
            else { continue }
            let cleaned = display.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            map[id] = cleaned
        }
        return map
    }

    private static func extractJSONArray(from text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start < end
        else { return nil }
        return String(text[start...end])
    }

    public static func sanitizeDisplay(_ text: String, locale: String) -> String {
        AIHintKeywordExtractor.finalize(text, locale: locale)
    }

    public static func fallbackTruncate(_ text: String, locale: String) -> String {
        AIHintKeywordExtractor.finalize(text, locale: locale)
    }
}
