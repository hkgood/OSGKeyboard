// AIHintLocalCatalog.swift
// OSGKeyboard · Shared
//
// Built-in current-information fallbacks for AI idle. Always available when
// the remote pack is missing or stale; clipboard actions live in Skills.

import Foundation

public enum AIHintLocalCatalog: Sendable {
    public static func cards(locale: String) -> [AIHintCard] {
        locale == "zh" ? zhCards : enCards
    }

    /// Prevent removed built-ins from resurfacing from a ready pack written by
    /// an older app version before the next successful cloud refresh.
    public static func isRetired(cardID: String) -> Bool {
        retiredCardIDs.contains(cardID)
    }

    private static let zhCards: [AIHintCard] = [
        AIHintCard(
            id: "local-zh-daily-brief",
            displayText: "今日早报",
            prompt: "请用中文写一份简洁的「今日早报」：国内外各 2–3 条要点、一条财经/科技、"
                + "一条轻松话题；每条一句话，总计不超过 12 句。不确定处请标明。",
            category: "daily",
            priority: 45,
            source: "local",
            locale: "zh",
            taskKind: .currentInformationQuestion
        ),
        AIHintCard(
            id: "local-zh-stocks-cn",
            displayText: "今日A股",
            prompt: "请用非专业口吻概括今天 A 股的整体表现，说明上证指数、深证成指或创业板的主要变化、"
                + "可能驱动因素，并提醒这并非投资建议（4-6 句）。",
            category: "economy",
            priority: 44,
            source: "local",
            locale: "zh",
            taskKind: .currentInformationQuestion
        ),
        AIHintCard(
            id: "local-zh-stocks-hk",
            displayText: "今日港股",
            prompt: "请用非专业口吻概括今天港股的整体表现，说明恒生指数、恒生科技指数的主要变化、"
                + "可能驱动因素，并提醒这并非投资建议（4-6 句）。",
            category: "economy",
            priority: 43,
            source: "local",
            locale: "zh",
            taskKind: .currentInformationQuestion
        ),
        AIHintCard(
            id: "local-zh-stocks-us",
            displayText: "今日美股",
            prompt: "请用非专业口吻概括今天或最近一个交易日美股的整体表现，说明道琼斯指数、标普 500、"
                + "纳斯达克指数的主要变化、可能驱动因素，并提醒这并非投资建议（4-6 句）。",
            category: "economy",
            priority: 42,
            source: "local",
            locale: "zh",
            taskKind: .currentInformationQuestion
        )
    ]

    private static let enCards: [AIHintCard] = [
        AIHintCard(
            id: "local-en-daily-brief",
            displayText: "Today's briefing",
            prompt: "Write a short daily briefing in English: 2–3 world items, one business/tech item, "
                + "and one light topic. One sentence each, at most 12 sentences. Mark uncertainty.",
            category: "daily",
            priority: 45,
            source: "local",
            locale: "en",
            taskKind: .currentInformationQuestion
        ),
        AIHintCard(
            id: "local-en-stocks-cn",
            displayText: "China A-shares",
            prompt: "Summarize today's China A-share market in plain English, including the main move in the "
                + "Shanghai Composite, Shenzhen Component, or ChiNext, likely drivers, and a reminder that "
                + "this is not financial advice (4-6 sentences).",
            category: "economy",
            priority: 44,
            source: "local",
            locale: "en",
            taskKind: .currentInformationQuestion
        ),
        AIHintCard(
            id: "local-en-stocks-hk",
            displayText: "Hong Kong stocks",
            prompt: "Summarize today's Hong Kong stock market in plain English, including the main moves in "
                + "the Hang Seng Index and Hang Seng TECH Index, likely drivers, and a reminder that this is "
                + "not financial advice (4-6 sentences).",
            category: "economy",
            priority: 43,
            source: "local",
            locale: "en",
            taskKind: .currentInformationQuestion
        ),
        AIHintCard(
            id: "local-en-stocks-us",
            displayText: "US stocks",
            prompt: "Summarize today's or the latest US stock-market session in plain English, including the "
                + "main moves in the Dow, S&P 500, and Nasdaq, likely drivers, and a reminder that this is not "
                + "financial advice (4-6 sentences).",
            category: "economy",
            priority: 42,
            source: "local",
            locale: "en",
            taskKind: .currentInformationQuestion
        )
    ]

    private static let retiredCardIDs: Set<String> = [
        "local-zh-clipboard-reply",
        "local-zh-clipboard-translate",
        "local-zh-clipboard-summarize",
        "local-zh-encyclopedia",
        "local-zh-stocks",
        "local-zh-quote",
        "local-zh-howto",
        "local-en-clipboard-reply",
        "local-en-clipboard-translate",
        "local-en-clipboard-summarize",
        "local-en-encyclopedia",
        "local-en-stocks",
        "local-en-quote",
        "local-en-howto"
    ]
}
