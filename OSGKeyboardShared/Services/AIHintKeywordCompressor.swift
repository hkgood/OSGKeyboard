// AIHintKeywordCompressor.swift
// OSGKeyboard · Shared
//
// Uses the user's polish LLM to compress remote hint titles into one-line
// display labels. Failure leaves the previous ready pack untouched (caller).

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
        let candidates = cards.filter { shouldCompress($0) }
        guard !candidates.isEmpty else { return cards }

        do {
            let client = try resolveClient()
            let payload = candidates.map {
                [
                    "id": $0.id,
                    "text": $0.displayText,
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
            guard !mapping.isEmpty else { return cards }
            return cards.map { card in
                guard let display = mapping[card.id], !display.isEmpty else { return card }
                var copy = card
                copy.displayText = Self.sanitizeDisplay(display, locale: locale)
                return copy
            }
        } catch {
            #if DEBUG
            print("⚠️ [AIHintKeywordCompressor] failed: \(error)")
            #endif
            return cards.map { card in
                var copy = card
                copy.displayText = Self.fallbackTruncate(card.displayText, locale: locale)
                return copy
            }
        }
    }

    private func shouldCompress(_ card: AIHintCard) -> Bool {
        if isHistoricalToday(card) { return false }
        if card.locale == "zh" || card.displayText.contains(where: { $0.isCJKUnifiedIdeograph }) {
            return card.displayText.count > 12 || card.displayText.contains("…")
                || card.displayText.contains("全网热点")
        }
        return card.displayText.count > 28
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
            你是输入法 AI 空闲轮播的文案压缩器。
            输入是 JSON 数组，每项含 id/text/category/source。
            输出 JSON 数组，每项仅 {"id","displayText"}。

            硬性规则：
            - displayText 必须单行，不要省略号结尾
            - 中文约 5–12 字
            - 按意图选句式，禁止统一加「聊聊」前缀：
              · 讨论类热点 →「聊聊+实体」
              · 剪贴板动作 →「帮我回复剪贴板」「把剪贴板译成英文」等
              · 天气查询 →「上海天气怎么样」
              · 早报/行情 →「看今日早报」「今天大盘如何」
              · 生成类 →「来句今日金句」「讲个有趣概念」
              · 节日 →「中秋节怎么过」
            - 丢弃「历史上的今天」类条目（不要输出它们的 id）
            - 不要改写 prompt；不要 Markdown；只输出 JSON
            """
        }
        return """
        You compress AI keyboard idle hint titles.
        Input: JSON array of {id,text,category,source}.
        Output: JSON array of {"id","displayText"} only.

        Rules:
        - displayText must be one line, no trailing ellipsis
        - English: ≤28 characters, NO "Chat"/"Chat about" prefix
        - Match intent (action / query / discuss) with a short natural label
        - Drop "On this day" / historical-today style items (omit their ids)
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
        var value = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("…") || value.hasSuffix("...") {
            if value.hasSuffix("...") {
                value = String(value.dropLast(3))
            } else {
                value = String(value.dropLast())
            }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallbackTruncate(value, locale: locale)
    }

    public static func fallbackTruncate(_ text: String, locale: String) -> String {
        let limit = locale == "zh" ? 12 : 28
        guard text.count > limit else { return text }
        return String(text.prefix(limit))
    }
}

private extension Character {
    var isCJKUnifiedIdeograph: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
    }
}
