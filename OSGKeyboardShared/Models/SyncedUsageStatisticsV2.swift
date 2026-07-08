// SyncedUsageStatisticsV2.swift
// OSGKeyboard · Shared
//
// Per-device grow-only counters (G-Counter) for cumulative usage stats.

import Foundation

public struct UsageStatisticsDeviceSlice: Codable, Equatable, Sendable {
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

    public static func merge(local: UsageStatisticsDeviceSlice, remote: UsageStatisticsDeviceSlice) -> UsageStatisticsDeviceSlice {
        UsageStatisticsDeviceSlice(
            updatedAt: max(local.updatedAt, remote.updatedAt),
            dictationDurationSeconds: max(local.dictationDurationSeconds, remote.dictationDurationSeconds),
            dictationCharacterCount: max(local.dictationCharacterCount, remote.dictationCharacterCount),
            translationCharacterCount: max(local.translationCharacterCount, remote.translationCharacterCount)
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
