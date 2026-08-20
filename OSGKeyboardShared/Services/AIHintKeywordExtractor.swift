// AIHintKeywordExtractor.swift
// OSGKeyboard · Shared
//
// Deterministic idle-chip labels: the icon carries type, the text is the
// entity. LLM compression is only a last resort for leftovers.

import Foundation

public enum AIHintKeywordExtractor: Sendable {
    public static func characterLimit(locale: String) -> Int {
        locale == "zh" ? 10 : 22
    }

    public static func displayText(for card: AIHintCard) -> String {
        let locale = card.locale == "zh" ? "zh" : "en"
        let kind = AIHintVisualKind.resolve(card)
        let raw = keyword(for: card, kind: kind, locale: locale)
        return finalize(raw, locale: locale)
    }

    /// Strip prefixes, pick a fitting chunk, then enforce the character cap.
    public static func finalize(_ text: String, locale: String) -> String {
        var value = stripPrefixes(text, locale: locale)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        value = stripTrailingPunctuation(value)
        let limit = characterLimit(locale: locale)
        if value.count <= limit { return value }
        if let clause = firstFittingClause(value, limit: limit) { return clause }
        if let latin = leadingLatinPhrase(value, limit: limit) { return latin }
        if let chunk = lastFittingChunk(value, limit: limit) { return chunk }
        return String(value.prefix(limit))
    }

    // MARK: - Keyword by kind

    private static func keyword(
        for card: AIHintCard,
        kind: AIHintVisualKind,
        locale: String
    ) -> String {
        switch kind {
        case .trending:
            return firstNonEmpty(card.metadata?.title, card.displayText)
        case .weather:
            if let city = trimmed(card.metadata?.city) {
                if let temp = card.metadata?.tempC {
                    return "\(city) \(Int(temp.rounded()))°"
                }
                return city
            }
            return card.displayText
        case .news:
            return locale == "zh" ? "今日早报" : "Today's briefing"
        case .stocks:
            return locale == "zh" ? "今日大盘" : "Markets"
        case .calendar:
            if locale != "zh", let name = trimmed(card.metadata?.name) {
                return name
            }
            return card.displayText
        case .search:
            if card.metadata?.soul != nil {
                return locale == "zh" ? "今日金句" : "A quote"
            }
            return card.displayText
        }
    }

    // MARK: - Prefixes

    public static func stripPrefixes(_ text: String, locale: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = locale == "zh" ? zhPrefixes : enPrefixes
        var changed = true
        while changed {
            changed = false
            for prefix in prefixes where value.hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                changed = true
                break
            }
        }
        return value
    }

    private static let zhPrefixes = [
        "全网热点：", "全网热点:", "临近节日：", "临近节日:",
        "历史上的今天：", "历史上的今天:", "今日一句：", "今日一句:",
        "查百科：", "查百科:", "聊聊", "看看"
    ]

    private static let enPrefixes = [
        "Trending: ", "Upcoming: ", "On this day: ",
        "Chat about ", "Chat ", "Weather in "
    ]

    // MARK: - Chunks

    private static func firstFittingClause(_ text: String, limit: Int) -> String? {
        let separators = CharacterSet(charactersIn: "，。；;,.!?？！")
        let parts = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let first = parts.first, first.count <= limit, first.count >= 2 else {
            return nil
        }
        return first
    }

    private static func lastFittingChunk(_ text: String, limit: Int) -> String? {
        let parts = text.split { $0 == " " || $0 == "：" || $0 == ":" }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }
        let cleaned = stripTrailingPunctuation(last)
        guard (4...limit).contains(cleaned.count) else { return nil }
        return cleaned
    }

    private static func leadingLatinPhrase(_ text: String, limit: Int) -> String? {
        var scalars: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            let isLatin = (0x41...0x5A).contains(scalar.value)
                || (0x61...0x7A).contains(scalar.value)
                || (0x30...0x39).contains(scalar.value)
                || scalar == "." || scalar == "-"
            let isSpace = scalar == " "
            if isLatin || (isSpace && !scalars.isEmpty) {
                scalars.append(scalar)
            } else if !scalars.isEmpty {
                break
            }
        }
        var phrase = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespaces)
        guard phrase.count >= 2 else { return nil }
        if phrase.count <= limit { return phrase }
        while phrase.count > limit {
            guard let lastSpace = phrase.lastIndex(of: " "), lastSpace > phrase.startIndex else {
                return String(phrase.prefix(limit))
            }
            phrase = String(phrase[..<lastSpace])
        }
        return phrase
    }

    private static func stripTrailingPunctuation(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "…。.!?？！、,"))
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        values.compactMap(trimmed).first ?? ""
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
