// UsageStatistics.swift
// OSGKeyboard · Shared
//
// Cumulative dictation metrics shown on the home / dashboard stats cards.
// Mirrored through iCloud KVS when settings sync is enabled.

import Foundation

public struct UsageStatistics: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var dictationDurationSeconds: TimeInterval
    public var dictationCharacterCount: Int
    public var translationCharacterCount: Int

    public init(
        updatedAt: Date = Date(),
        dictationDurationSeconds: TimeInterval = 0,
        dictationCharacterCount: Int = 0,
        translationCharacterCount: Int = 0
    ) {
        self.updatedAt = updatedAt
        self.dictationDurationSeconds = dictationDurationSeconds
        self.dictationCharacterCount = dictationCharacterCount
        self.translationCharacterCount = translationCharacterCount
    }

    public static let zero = UsageStatistics(updatedAt: .distantPast)

    /// Combine lifetime totals from two devices. After merge, each device
    /// continues accumulating locally so `max` converges to the union.
    public static func merge(local: UsageStatistics, remote: UsageStatistics) -> UsageStatistics {
        UsageStatistics(
            updatedAt: max(local.updatedAt, remote.updatedAt),
            dictationDurationSeconds: max(local.dictationDurationSeconds, remote.dictationDurationSeconds),
            dictationCharacterCount: max(local.dictationCharacterCount, remote.dictationCharacterCount),
            translationCharacterCount: max(local.translationCharacterCount, remote.translationCharacterCount)
        )
    }
}

public enum UsageStatisticsStorage {
    public static let storageKey = "usageStatistics.v1"
    /// Legacy macOS dashboard counter (word split); migrated on first load.
    public static let legacyMacTotalWordsKey = "mac.totalWords"
    /// Pre–App Group iOS storage in `UserDefaults.standard`.
    public static let legacyStandardDefaultsKey = "usageStatistics.v1"

    public static func load(from defaults: UserDefaults) -> UsageStatistics {
        if let data = defaults.data(forKey: storageKey),
           let stats = try? JSONDecoder().decode(UsageStatistics.self, from: data) {
            return stats
        }
        return .zero
    }

    public static func save(_ stats: UsageStatistics, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// One-time imports from older per-platform keys.
    public static func migrateLegacyIfNeeded(into defaults: UserDefaults) -> UsageStatistics {
        var stats = load(from: defaults)
        guard stats == .zero else { return stats }

        let legacyWords = defaults.integer(forKey: legacyMacTotalWordsKey)
        if legacyWords > 0 {
            stats.dictationCharacterCount = legacyWords
            stats.updatedAt = Date()
            save(stats, to: defaults)
            return stats
        }

        #if os(iOS)
        if let data = UserDefaults.standard.data(forKey: legacyStandardDefaultsKey),
           let legacy = try? JSONDecoder().decode(UsageStatistics.self, from: data),
           legacy != .zero {
            stats = legacy
            stats.updatedAt = Date()
            save(stats, to: defaults)
        }
        #endif

        return stats
    }
}
