// UsageStatisticsStore.swift
// OSGKeyboard · Shared
//
// Observable store for cumulative usage metrics. Updated after each
// successful dictation on iOS Flow and macOS menu-bar capture.

import Combine
import Foundation

@MainActor
public final class UsageStatisticsStore: ObservableObject {
    public static let shared = UsageStatisticsStore()

    @Published public private(set) var dictationDurationSeconds: TimeInterval = 0
    @Published public private(set) var dictationCharacterCount: Int = 0
    @Published public private(set) var translationCharacterCount: Int = 0

    public let defaults: UserDefaults

    /// Marks the one-time purge of statistics corrupted by the pre-fix
    /// double-counting bug (see `purgeCorruptedStatsIfNeeded`).
    private static let dirtyResetFlagKey = "usageStatistics.dirtyReset.v1"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? AppGroupStore().defaults
        purgeCorruptedStatsIfNeeded()
        reloadFromDisk()
        NotificationCenter.default.addObserver(
            forName: .usageStatisticsDidSyncFromCloud,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
    }

    public func recordUtterance(text: String, duration: TimeInterval, wasTranslation: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let count = Self.characterCount(for: trimmed)

        // Increment ONLY this device's own slice. The displayed totals are the
        // cross-device *sum* (see `reloadFromDisk`), so incrementing in-memory
        // display state and writing it back as this device's slice would fold
        // every other device's total into this one and double-count on the
        // next reload — the bug that inflated one slice to ~8× the real usage.
        let deviceID = SyncDeviceID.current(defaults: defaults)
        var slice = SyncedUsageStatisticsStorage.currentDeviceSlice(from: defaults, deviceID: deviceID)
        if wasTranslation {
            slice.translationCharacterCount += count
        } else {
            slice.dictationCharacterCount += count
        }
        slice.dictationDurationSeconds += max(0, duration)
        slice.updatedAt = Date()
        SyncedUsageStatisticsStorage.upsertCurrentDeviceSlice(slice, defaults: defaults, deviceID: deviceID)

        reloadFromDisk()

        Task {
            try? await UsageStatisticsCloudSync.shared.pushLocalIfEnabled()
        }
    }

    /// Refreshes the published totals from disk. Display-only: it reads the
    /// aggregated cross-device sum and NEVER writes it back (writing would
    /// corrupt the per-device slices — see `recordUtterance`).
    public func reloadFromDisk() {
        let aggregated = SyncedUsageStatisticsStorage.load(from: defaults).aggregated
        dictationDurationSeconds = aggregated.dictationDurationSeconds
        dictationCharacterCount = aggregated.dictationCharacterCount
        translationCharacterCount = aggregated.translationCharacterCount
    }

    /// One-time cleanup: the pre-fix code overwrote a device slice with the
    /// cross-device *sum*, so every reload/record re-added the other devices'
    /// totals and one slice ballooned to ~8× the true usage. We can't recover
    /// the true per-device split from corrupted data, so wipe local + remote
    /// once and let the corrected per-device accounting re-accumulate cleanly.
    private func purgeCorruptedStatsIfNeeded() {
        guard !defaults.bool(forKey: Self.dirtyResetFlagKey) else { return }
        defaults.set(true, forKey: Self.dirtyResetFlagKey)

        defaults.removeObject(forKey: SyncedUsageStatisticsStorage.storageKey)
        defaults.removeObject(forKey: UsageStatisticsStorage.storageKey)
        defaults.removeObject(forKey: UsageStatisticsStorage.legacyMacTotalWordsKey)

        UsageStatisticsCloudSync.shared.purgeRemote()
    }

    public static func characterCount(for text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    // MARK: - Formatting

    public static func formatDuration(_ seconds: TimeInterval, language: AppUILanguage) -> String {
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

    public static func formatCount(_ value: Int, language: AppUILanguage) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: language.resolvedLanguageCode())
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
