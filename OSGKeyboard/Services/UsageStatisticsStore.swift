// UsageStatisticsStore.swift
// OSGKeyboard · Main App
//
// Cumulative usage metrics shown on the home screen stats card.
// Updated when Flow finalizes a successful utterance.

import Foundation
import Combine

struct UsageStatistics: Codable, Equatable {
    var dictationDurationSeconds: TimeInterval
    var dictationCharacterCount: Int
    var translationCharacterCount: Int

    static let zero = UsageStatistics(
        dictationDurationSeconds: 0,
        dictationCharacterCount: 0,
        translationCharacterCount: 0
    )
}

@MainActor
final class UsageStatisticsStore: ObservableObject {
    static let shared = UsageStatisticsStore()

    @Published private(set) var dictationDurationSeconds: TimeInterval = 0
    @Published private(set) var dictationCharacterCount: Int = 0
    @Published private(set) var translationCharacterCount: Int = 0

    private let defaults: UserDefaults
    private let storageKey = "usageStatistics.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func recordUtterance(text: String, duration: TimeInterval, wasTranslation: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let count = Self.characterCount(for: trimmed)
        if wasTranslation {
            translationCharacterCount += count
        } else {
            dictationCharacterCount += count
        }
        dictationDurationSeconds += max(0, duration)
        persist()
    }

    static func characterCount(for text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    // MARK: - Formatting

    static func formatDuration(_ seconds: TimeInterval, language: AppUILanguage) -> String {
        let total = max(0, Int(seconds.rounded()))
        if total < 60 {
            return language.resolvedLanguageCode().hasPrefix("zh")
                ? "\(total)秒"
                : "\(total)s"
        }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return language.resolvedLanguageCode().hasPrefix("zh")
                ? "\(hours)小时\(minutes)分"
                : "\(hours)h \(minutes)m"
        }
        return language.resolvedLanguageCode().hasPrefix("zh")
            ? "\(minutes)分"
            : "\(minutes)m"
    }

    static func formatCount(_ value: Int, language: AppUILanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language.resolvedLanguageCode())
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let stats = try? JSONDecoder().decode(UsageStatistics.self, from: data)
        else { return }
        dictationDurationSeconds = stats.dictationDurationSeconds
        dictationCharacterCount = stats.dictationCharacterCount
        translationCharacterCount = stats.translationCharacterCount
    }

    private func persist() {
        let stats = UsageStatistics(
            dictationDurationSeconds: dictationDurationSeconds,
            dictationCharacterCount: dictationCharacterCount,
            translationCharacterCount: translationCharacterCount
        )
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
