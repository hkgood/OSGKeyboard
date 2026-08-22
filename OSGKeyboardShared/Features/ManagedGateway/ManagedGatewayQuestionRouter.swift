// ManagedGatewayQuestionRouter.swift
// OSGKeyboard · Shared
//
// Deterministic, on-device routing for questions that cannot be answered
// reliably without current information. No prompt content is persisted.

import Foundation

public enum ManagedGatewayQuestionRouter {
    public static func taskKind(
        for question: String,
        requestedTaskKind: ManagedGatewayTaskKind = .aiQuestion
    ) -> ManagedGatewayTaskKind {
        guard requestedTaskKind == .aiQuestion else { return requestedTaskKind }
        return requiresCurrentInformation(question)
            ? .currentInformationQuestion
            : .aiQuestion
    }

    public static func requiresCurrentInformation(_ question: String) -> Bool {
        let normalized = question
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if strongCurrentSignals.contains(where: normalized.contains) {
            return true
        }
        let hasTemporalSignal = temporalSignals.contains(where: normalized.contains)
        let hasCurrentSubject = currentSubjects.contains(where: normalized.contains)
        return hasTemporalSignal && hasCurrentSubject
    }

    private static let strongCurrentSignals = [
        "最新", "实时", "热点", "头条", "热搜", "要闻", "路况",
        "breaking news", "latest news", "current events", "live score",
        "stock price", "exchange rate", "traffic conditions"
    ]

    private static let temporalSignals = [
        "昨天", "今天", "今日", "今晚", "明天", "后天", "现在", "当前",
        "此刻", "刚刚", "最近", "本周", "本周末", "本月", "今年",
        "yesterday", "today", "tonight", "tomorrow", "right now",
        "currently", "recent", "this week", "this weekend", "this month", "this year"
    ]

    private static let currentSubjects = [
        "新闻", "天气", "气温", "下雨", "台风", "股价", "股票", "大盘",
        "汇率", "价格", "票价",
        "比分", "赛果", "排名", "航班", "油价", "金价", "发生", "大事",
        "news", "weather", "temperature", "price", "score", "ranking",
        "flight", "forecast", "what happened"
    ]
}
