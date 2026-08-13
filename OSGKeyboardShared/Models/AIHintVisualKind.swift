// AIHintVisualKind.swift
// OSGKeyboard · Shared
//
// Maps hint-feed category/source onto the idle-chip SF Symbol.

import Foundation

public enum AIHintVisualKind: String, Equatable, Sendable {
    case calendar
    case weather
    case news
    case stocks
    case trending
    case search

    public var systemImage: String {
        switch self {
        case .calendar: return "calendar"
        case .weather: return "cloud.sun.fill"
        case .news: return "newspaper.fill"
        case .stocks: return "chart.line.uptrend.xyaxis"
        case .trending: return "flame.fill"
        case .search: return "magnifyingglass"
        }
    }

    public static func resolve(_ card: AIHintCard) -> Self {
        let category = card.category.lowercased()
        let source = card.source.lowercased()
        let id = card.id.lowercased()

        if category == "weather" || source.contains("meteo") {
            return .weather
        }
        if category == "economy" || id.contains("stock") {
            return .stocks
        }
        if category == "society"
            || source.contains("open-hot")
            || source.contains("tophub-open") {
            return .trending
        }
        if category == "holiday"
            || category == "history"
            || source.contains("holiday")
            || card.conditions.contains("date") {
            return .calendar
        }
        if category == "daily" {
            if card.metadata?.soul != nil || id.contains("soul") {
                return .search
            }
            return .news
        }
        // Quotes, encyclopedia, how-to, and unknown capability cards.
        return .search
    }
}
