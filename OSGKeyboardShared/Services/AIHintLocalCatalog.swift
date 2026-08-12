// AIHintLocalCatalog.swift
// OSGKeyboard · Shared
//
// Built-in, non-time-sensitive AI idle hints (clipboard + evergreen). Always
// available as a fallback when the remote pack is missing or stale.

import Foundation

public enum AIHintLocalCatalog: Sendable {
    public static func cards(locale: String) -> [AIHintCard] {
        locale == "zh" ? zhCards : enCards
    }

    private static let zhCards: [AIHintCard] = [
        AIHintCard(
            id: "local-zh-clipboard-reply",
            displayText: "帮我回复剪贴板",
            prompt: "请根据剪贴板内容起草一段礼貌、简洁的回复，语气自然，可直接发送。",
            category: "clipboard",
            priority: 90,
            source: "local",
            locale: "zh",
            conditions: ["clipboard_30s"]
        ),
        AIHintCard(
            id: "local-zh-clipboard-translate",
            displayText: "把剪贴板译成英文",
            prompt: "请将剪贴板内容翻译成自然、地道的英文，保留原意与语气。",
            category: "clipboard",
            priority: 88,
            source: "local",
            locale: "zh",
            conditions: ["clipboard_30s"]
        ),
        AIHintCard(
            id: "local-zh-clipboard-summarize",
            displayText: "帮我精简剪贴板",
            prompt: "请将剪贴板内容精简为更短、更清晰的版本，保留关键信息与语气。",
            category: "clipboard",
            priority: 86,
            source: "local",
            locale: "zh",
            conditions: ["clipboard_30s"]
        ),
        AIHintCard(
            id: "local-zh-encyclopedia",
            displayText: "讲个有趣概念",
            prompt: "用通俗易懂的中文解释一个有趣但常见的概念，并给一个生活里的例子（4-6 句）。",
            category: "capability",
            priority: 40,
            source: "local",
            locale: "zh"
        ),
        AIHintCard(
            id: "local-zh-stocks",
            displayText: "今天大盘如何",
            prompt: "请用非专业口吻概括今天 A 股/港股/美股中至少一个市场的整体表现、"
                + "可能驱动因素，并提醒这并非投资建议（4-6 句）。",
            category: "economy",
            priority: 42,
            source: "local",
            locale: "zh"
        ),
        AIHintCard(
            id: "local-zh-daily-brief",
            displayText: "看今日早报",
            prompt: "请用中文写一份简洁的「今日早报」：国内外各 2–3 条要点、一条财经/科技、"
                + "一条轻松话题；每条一句话，总计不超过 12 句。不确定处请标明。",
            category: "daily",
            priority: 45,
            source: "local",
            locale: "zh"
        ),
        AIHintCard(
            id: "local-zh-quote",
            displayText: "来句今日金句",
            prompt: "请给一句适合今天分享的中文金句，并附上一两句简短解释。",
            category: "capability",
            priority: 38,
            source: "local",
            locale: "zh"
        ),
        AIHintCard(
            id: "local-zh-howto",
            displayText: "给我一个小技巧",
            prompt: "分享一个实用的生活或工作效率小技巧，用中文说清步骤与适用场景（4-6 句）。",
            category: "capability",
            priority: 36,
            source: "local",
            locale: "zh"
        ),
    ]

    private static let enCards: [AIHintCard] = [
        AIHintCard(
            id: "local-en-clipboard-reply",
            displayText: "Reply to clipboard",
            prompt: "Draft a concise, polite reply the user can send, based on the clipboard text.",
            category: "clipboard",
            priority: 90,
            source: "local",
            locale: "en",
            conditions: ["clipboard_30s"]
        ),
        AIHintCard(
            id: "local-en-clipboard-translate",
            displayText: "Translate clipboard",
            prompt: "Translate the clipboard text into natural English, preserving meaning and tone.",
            category: "clipboard",
            priority: 88,
            source: "local",
            locale: "en",
            conditions: ["clipboard_30s"]
        ),
        AIHintCard(
            id: "local-en-clipboard-summarize",
            displayText: "Shorten clipboard",
            prompt: "Shorten the clipboard text into a clearer, shorter version while keeping the key points.",
            category: "clipboard",
            priority: 86,
            source: "local",
            locale: "en",
            conditions: ["clipboard_30s"]
        ),
        AIHintCard(
            id: "local-en-encyclopedia",
            displayText: "Explain a concept",
            prompt: "Explain an interesting everyday concept in plain English with one real-life example (4-6 sentences).",
            category: "capability",
            priority: 40,
            source: "local",
            locale: "en"
        ),
        AIHintCard(
            id: "local-en-stocks",
            displayText: "Market pulse",
            prompt: "Summarize today's broad market mood (US or global) in plain English, "
                + "note possible drivers, and add this is not financial advice (4-6 sentences).",
            category: "economy",
            priority: 42,
            source: "local",
            locale: "en"
        ),
        AIHintCard(
            id: "local-en-daily-brief",
            displayText: "Today's briefing",
            prompt: "Write a short daily briefing in English: 2–3 world items, one business/tech item, "
                + "and one light topic. One sentence each, at most 12 sentences. Mark uncertainty.",
            category: "daily",
            priority: 45,
            source: "local",
            locale: "en"
        ),
        AIHintCard(
            id: "local-en-quote",
            displayText: "Share a quote",
            prompt: "Share one short quote worth sending today, plus one or two sentences of context.",
            category: "capability",
            priority: 38,
            source: "local",
            locale: "en"
        ),
        AIHintCard(
            id: "local-en-howto",
            displayText: "Give a tip",
            prompt: "Share one practical life or productivity tip in English, with steps and when it helps (4-6 sentences).",
            category: "capability",
            priority: 36,
            source: "local",
            locale: "en"
        ),
    ]
}
