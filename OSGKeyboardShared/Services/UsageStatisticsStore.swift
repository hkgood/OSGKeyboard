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
    @Published public private(set) var aiCharacterCount: Int = 0
    public var totalInputCharacterCount: Int {
        dictationCharacterCount + translationCharacterCount + aiCharacterCount
    }
    /// Cross-device dictation characters per local day (`yyyy-MM-dd`), used by
    /// the home page and dashboard usage visualizations.
    @Published public private(set) var dailyDictationCharacters: [String: Int] = [:]

    /// How many days of daily buckets to retain on disk. This preserves several
    /// complete monthly views when a device syncs late.
    private static let dailyRetentionDays = 90

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
            let dayKey = UsageStatisticsDayKey.key(for: Date())
            slice.dailyDictationCharacters[dayKey, default: 0] += count
            UsageStatisticsDayKey.prune(&slice.dailyDictationCharacters, keepingDays: Self.dailyRetentionDays)
        }
        slice.dictationDurationSeconds += max(0, duration)
        slice.updatedAt = Date()
        SyncedUsageStatisticsStorage.upsertCurrentDeviceSlice(slice, defaults: defaults, deviceID: deviceID)

        reloadFromDisk()

        Task {
            try? await UsageStatisticsCloudSync.shared.pushLocalIfEnabled()
        }
    }

    /// Record an explicitly inserted AI answer exactly once. The commit id and
    /// counter update share one device-slice write, so outbox retries are safe.
    public func recordAIInsertion(text: String, commitID: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let deviceID = SyncDeviceID.current(defaults: defaults)
        var slice = SyncedUsageStatisticsStorage.currentDeviceSlice(
            from: defaults,
            deviceID: deviceID
        )
        guard !slice.appliedAICommitIDs.contains(commitID) else { return }

        slice.aiCharacterCount += Self.characterCount(for: trimmed)
        slice.appliedAICommitIDs.append(commitID)
        slice.appliedAICommitIDs = Array(slice.appliedAICommitIDs.suffix(128))
        slice.updatedAt = Date()
        SyncedUsageStatisticsStorage.upsertCurrentDeviceSlice(
            slice,
            defaults: defaults,
            deviceID: deviceID
        )

        reloadFromDisk()
        Task {
            try? await UsageStatisticsCloudSync.shared.pushLocalIfEnabled()
        }
    }

    /// Refreshes the published totals from disk. Display-only: it reads the
    /// aggregated cross-device sum and NEVER writes it back (writing would
    /// corrupt the per-device slices — see `recordUtterance`).
    public func reloadFromDisk() {
        let payload = SyncedUsageStatisticsStorage.load(from: defaults)
        let aggregated = payload.aggregated
        dictationDurationSeconds = aggregated.dictationDurationSeconds
        dictationCharacterCount = aggregated.dictationCharacterCount
        translationCharacterCount = aggregated.translationCharacterCount
        aiCharacterCount = aggregated.aiCharacterCount
        dailyDictationCharacters = payload.aggregatedDailyDictationCharacters
    }

    // MARK: - Daily chart data

    /// One day's dictation total for home and dashboard visualizations.
    public struct DailyUsagePoint: Identifiable, Equatable, Sendable {
        public let date: Date
        public let value: Int
        public var id: Date { date }

        public init(date: Date, value: Int) {
            self.date = date
            self.value = value
        }
    }

    /// The trailing 7 local days (oldest → newest), zero-filled for days with no
    /// dictation, so the chart always renders a full week.
    public var last7Days: [DailyUsagePoint] {
        Self.last7Days(from: dailyDictationCharacters)
    }

    public static func last7Days(
        from daily: [String: Int],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyUsagePoint] {
        let startOfToday = calendar.startOfDay(for: now)
        var points: [DailyUsagePoint] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: startOfToday) else { continue }
            let key = UsageStatisticsDayKey.key(for: day, calendar: calendar)
            points.append(DailyUsagePoint(date: day, value: daily[key] ?? 0))
        }
        return points
    }

    /// Every local-calendar day in the current month, including future days.
    /// Missing buckets are zero-filled so the UI can always render a complete
    /// calendar instead of changing shape as usage accumulates.
    public var currentMonth: [DailyUsagePoint] {
        Self.currentMonth(from: dailyDictationCharacters)
    }

    public static func currentMonth(
        from daily: [String: Int],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyUsagePoint] {
        let monthComponents = calendar.dateComponents([.year, .month], from: now)
        guard let monthStart = calendar.date(from: monthComponents),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart)
        else { return [] }

        return dayRange.compactMap { day in
            guard let date = calendar.date(
                byAdding: .day,
                value: day - 1,
                to: monthStart
            ) else { return nil }
            let key = UsageStatisticsDayKey.key(for: date, calendar: calendar)
            return DailyUsagePoint(date: date, value: daily[key] ?? 0)
        }
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
