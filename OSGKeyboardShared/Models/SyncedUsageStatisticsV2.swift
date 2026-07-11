// SyncedUsageStatisticsV2.swift
// OSGKeyboard · Shared
//
// Per-device grow-only counters (G-Counter) for cumulative usage stats.

import Foundation

/// Local-calendar day key (`yyyy-MM-dd`) for daily usage buckets. String keys
/// sort lexicographically in chronological order, which keeps pruning and
/// range queries index-free.
public enum UsageStatisticsDayKey {
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Drops buckets older than `days` so the synced blob stays small even
    /// after months of use (the chart only ever needs the last 7 days).
    public static func prune(_ daily: inout [String: Int], keepingDays days: Int, now: Date = Date(), calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: now) else { return }
        let cutoffKey = key(for: cutoff, calendar: calendar)
        daily = daily.filter { $0.key >= cutoffKey }
    }
}

public struct UsageStatisticsDeviceSlice: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var dictationDurationSeconds: TimeInterval
    public var dictationCharacterCount: Int
    public var translationCharacterCount: Int
    /// Grow-only per-day dictation character counts, keyed by local `yyyy-MM-dd`.
    /// Powers the home page's 7-day chart; merged per-key with `max` (each device
    /// only ever grows its own days) and summed across devices when aggregated.
    public var dailyDictationCharacters: [String: Int]

    public init(
        updatedAt: Date = Date(),
        dictationDurationSeconds: TimeInterval = 0,
        dictationCharacterCount: Int = 0,
        translationCharacterCount: Int = 0,
        dailyDictationCharacters: [String: Int] = [:]
    ) {
        self.updatedAt = updatedAt
        self.dictationDurationSeconds = dictationDurationSeconds
        self.dictationCharacterCount = dictationCharacterCount
        self.translationCharacterCount = translationCharacterCount
        self.dailyDictationCharacters = dailyDictationCharacters
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case dictationDurationSeconds
        case dictationCharacterCount
        case translationCharacterCount
        case dailyDictationCharacters
    }

    // Custom decode so slices written before the daily-buckets field still load
    // (the missing key defaults to an empty map rather than failing the decode).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        dictationDurationSeconds = try container.decode(TimeInterval.self, forKey: .dictationDurationSeconds)
        dictationCharacterCount = try container.decode(Int.self, forKey: .dictationCharacterCount)
        translationCharacterCount = try container.decode(Int.self, forKey: .translationCharacterCount)
        dailyDictationCharacters = try container.decodeIfPresent([String: Int].self, forKey: .dailyDictationCharacters) ?? [:]
    }

    public static func merge(local: UsageStatisticsDeviceSlice, remote: UsageStatisticsDeviceSlice) -> UsageStatisticsDeviceSlice {
        var mergedDaily = local.dailyDictationCharacters
        for (day, value) in remote.dailyDictationCharacters {
            mergedDaily[day] = max(mergedDaily[day] ?? 0, value)
        }
        return UsageStatisticsDeviceSlice(
            updatedAt: max(local.updatedAt, remote.updatedAt),
            dictationDurationSeconds: max(local.dictationDurationSeconds, remote.dictationDurationSeconds),
            dictationCharacterCount: max(local.dictationCharacterCount, remote.dictationCharacterCount),
            translationCharacterCount: max(local.translationCharacterCount, remote.translationCharacterCount),
            dailyDictationCharacters: mergedDaily
        )
    }

    public var totals: UsageStatistics {
        UsageStatistics(
            updatedAt: updatedAt,
            dictationDurationSeconds: dictationDurationSeconds,
            dictationCharacterCount: dictationCharacterCount,
            translationCharacterCount: translationCharacterCount
        )
    }
}

public struct SyncedUsageStatisticsV2: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let kvsKey = "usageStatistics.v2"

    public var schemaVersion: Int
    public var devices: [String: UsageStatisticsDeviceSlice]

    public init(schemaVersion: Int = Self.schemaVersion, devices: [String: UsageStatisticsDeviceSlice] = [:]) {
        self.schemaVersion = schemaVersion
        self.devices = devices
    }

    public static let empty = SyncedUsageStatisticsV2()

    public var aggregated: UsageStatistics {
        var duration: TimeInterval = 0
        var dictation = 0
        var translation = 0
        var latest = Date.distantPast
        for slice in devices.values {
            duration += slice.dictationDurationSeconds
            dictation += slice.dictationCharacterCount
            translation += slice.translationCharacterCount
            latest = max(latest, slice.updatedAt)
        }
        return UsageStatistics(
            updatedAt: latest,
            dictationDurationSeconds: duration,
            dictationCharacterCount: dictation,
            translationCharacterCount: translation
        )
    }

    /// Cross-device daily dictation characters (summed per `yyyy-MM-dd`).
    public var aggregatedDailyDictationCharacters: [String: Int] {
        var result: [String: Int] = [:]
        for slice in devices.values {
            for (day, value) in slice.dailyDictationCharacters {
                result[day, default: 0] += value
            }
        }
        return result
    }

    public static func merge(local: SyncedUsageStatisticsV2, remote: SyncedUsageStatisticsV2) -> SyncedUsageStatisticsV2 {
        var mergedDevices = local.devices
        for (deviceID, remoteSlice) in remote.devices {
            if let localSlice = mergedDevices[deviceID] {
                mergedDevices[deviceID] = .merge(local: localSlice, remote: remoteSlice)
            } else {
                mergedDevices[deviceID] = remoteSlice
            }
        }
        return SyncedUsageStatisticsV2(devices: mergedDevices)
    }

    public static func migrated(from legacy: UsageStatistics, deviceID: String) -> SyncedUsageStatisticsV2 {
        guard legacy != .zero else { return .empty }
        return SyncedUsageStatisticsV2(devices: [
            deviceID: UsageStatisticsDeviceSlice(
                updatedAt: legacy.updatedAt,
                dictationDurationSeconds: legacy.dictationDurationSeconds,
                dictationCharacterCount: legacy.dictationCharacterCount,
                translationCharacterCount: legacy.translationCharacterCount
            ),
        ])
    }
}

public enum SyncedUsageStatisticsStorage {
    public static let storageKey = SyncedUsageStatisticsV2.kvsKey
    public static let legacyStorageKey = "usageStatistics.v1"

    public static func load(from defaults: UserDefaults) -> SyncedUsageStatisticsV2 {
        if let data = defaults.data(forKey: storageKey),
           let payload = try? JSONDecoder().decode(SyncedUsageStatisticsV2.self, from: data) {
            return payload
        }
        return migrateLegacyIfNeeded(into: defaults)
    }

    public static func save(_ payload: SyncedUsageStatisticsV2, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }

    public static func migrateLegacyIfNeeded(into defaults: UserDefaults) -> SyncedUsageStatisticsV2 {
        let deviceID = SyncDeviceID.current(defaults: defaults)
        let legacy = UsageStatisticsStorage.migrateLegacyIfNeeded(into: defaults)
        let migrated = SyncedUsageStatisticsV2.migrated(from: legacy, deviceID: deviceID)
        if migrated != .empty {
            save(migrated, to: defaults)
        }
        return migrated
    }

    public static func currentDeviceSlice(
        from defaults: UserDefaults,
        deviceID: String? = nil
    ) -> UsageStatisticsDeviceSlice {
        let id = deviceID ?? SyncDeviceID.current(defaults: defaults)
        return load(from: defaults).devices[id] ?? UsageStatisticsDeviceSlice()
    }

    public static func upsertCurrentDeviceSlice(
        _ slice: UsageStatisticsDeviceSlice,
        defaults: UserDefaults,
        deviceID: String? = nil
    ) {
        let id = deviceID ?? SyncDeviceID.current(defaults: defaults)
        var payload = load(from: defaults)
        payload.devices[id] = slice
        save(payload, to: defaults)
    }
}
