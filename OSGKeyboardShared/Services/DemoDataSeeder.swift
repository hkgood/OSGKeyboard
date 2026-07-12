// DemoDataSeeder.swift
// OSGKeyboard · Shared
//
// DEBUG / screenshot helper: fills Home stats, History, and Dictionary with
// rich placeholder content, and forces iCloud sync OFF so a remote pull cannot
// wipe the seed. Trigger via `osgkeyboard://seed-demo`.

import Foundation

@MainActor
public enum DemoDataSeeder {
    /// Disable sync (local + KVS), write placeholder payloads, reload stores.
    public static func seedRichPlaceholderData(
        defaults: UserDefaults? = nil,
        historyDefaults: UserDefaults = .standard
    ) {
        let store = defaults.map { AppGroupStore(defaults: $0) } ?? AppGroupStore()
        let groupDefaults = store.defaults

        // 1. Sync must be OFF before any pull can empty the dictionary.
        store.setSettingsICloudSyncEnabled(false)
        store.setPersonalDictionaryICloudSyncEnabled(false)
        ICloudSyncPreferences.pushSettingsEnabled(false, kvs: NSUbiquitousKeyValueStore.default)
        ICloudSyncPreferences.pushDictionaryEnabled(false, kvs: NSUbiquitousKeyValueStore.default)

        groupDefaults.set(true, forKey: "usageStatistics.dirtyReset.v1")
        groupDefaults.set(true, forKey: "home.keyboardHintDismissed")
        groupDefaults.set(true, forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding)
        // Mac onboarding flag (harmless on iOS).
        groupDefaults.set(true, forKey: "mac.hasCompletedOnboarding")
        UserDefaults.standard.set(true, forKey: "mac.hasCompletedOnboarding")

        let now = Date()
        seedUsage(defaults: groupDefaults, now: now)
        seedHistory(defaults: historyDefaults, now: now)
        seedDictionary(store: store, now: now)

        UsageStatisticsStore(defaults: groupDefaults).reloadFromDisk()
        UsageStatisticsStore.shared.reloadFromDisk()
        SpeechHistoryStore(defaults: historyDefaults).reloadFromDisk()
        SpeechHistoryStore.shared.reloadFromDisk()

        NotificationCenter.default.post(name: .personalDictionaryDidSyncFromCloud, object: nil)
        NotificationCenter.default.post(name: .usageStatisticsDidSyncFromCloud, object: nil)
    }

    // MARK: - Payloads

    private static func seedUsage(defaults: UserDefaults, now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dailyValues = [2100, 3400, 1800, 5200, 2900, 6100, 4300]
        var daily: [String: Int] = [:]
        for (offset, value) in dailyValues.enumerated() {
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: today) else { continue }
            daily[UsageStatisticsDayKey.key(for: day)] = value
        }

        let deviceID = SyncDeviceID.current(defaults: defaults)
        let slice = UsageStatisticsDeviceSlice(
            updatedAt: now,
            dictationDurationSeconds: 6120,
            dictationCharacterCount: 31_458,
            translationCharacterCount: 3_200,
            dailyDictationCharacters: daily
        )
        SyncedUsageStatisticsStorage.upsertCurrentDeviceSlice(
            slice,
            defaults: defaults,
            deviceID: deviceID
        )
    }

    private static func seedHistory(defaults: UserDefaults, now: Date) {
        let samples: [(String, String)] = [
            ("local", "请帮我把这段会议纪要整理成三条行动项，并标出负责人。"),
            ("local", "下周产品评审改到周三下午两点，地点还是三楼会议室。"),
            ("cloud", "帮我写一封礼貌的跟进邮件，询问合同进度。"),
            ("local", "今天听写了三十分钟，词库命中率比昨天更好。"),
            ("local", "把「开口即文字」加到品牌口号里，首页和引导页保持一致。"),
            ("cloud", "Draft a short release note for the appearance preference on iOS and iPad."),
            ("local", "提醒我晚上九点前提交 App Store 截图和落地页更新。"),
            ("local", "语音输入在任意 App 可用，点按键盘麦克风即可开始听写。"),
            ("cloud", "Summarize yesterday's dictation stats for the weekly report."),
            ("local", "词库里加上 Cursor、DeepSeek、Qwen3-ASR，方便识别专有名词。"),
            ("local", "跨设备同步先关掉，演示数据用本地占位，避免被 iCloud 覆盖。"),
            ("local", "把首页近七天柱状图补齐，看起来更有真实使用痕迹。"),
        ]

        var entries: [SpeechHistoryEntry] = []
        for (index, pair) in samples.enumerated() {
            let created = now.addingTimeInterval(-Double(index * 5 * 3600 + index * 7 * 60))
            entries.append(
                SpeechHistoryEntry(
                    id: UUID(),
                    text: pair.1,
                    createdAt: created,
                    engineMode: pair.0
                )
            )
        }

        var history = SyncedSpeechHistory(updatedAt: now)
        history.entries = entries
        history.deletedEntryIDs = [:]
        SpeechHistoryStorage.save(history, to: defaults)
    }

    private static func seedDictionary(store: AppGroupStore, now: Date) {
        let terms: [(String, [String], PersonalDictionary.Entry.Category, Int)] = [
            ("OSGKeyboard", ["OSG Keyboard", "开口即文字"], .productName, 48),
            ("Cursor", ["cursor"], .productName, 36),
            ("DeepSeek", ["deep seek", "深度求索"], .productName, 29),
            ("Qwen3-ASR", ["千问 ASR", "Qwen ASR"], .technical, 22),
            ("BYOK", ["自带密钥"], .acronym, 18),
            ("Sherpa", ["sherpa onnx"], .technical, 15),
            ("Typeless", [], .productName, 11),
            ("iCloud", ["云同步"], .productName, 9),
            ("SpeechAnalyzer", ["语音分析器"], .technical, 7),
            ("Live Activity", ["灵动岛"], .custom, 5),
            ("StoreKit", ["内购"], .technical, 4),
            ("Rocky", ["rocky"], .properNoun, 3),
        ]

        var dictionary = PersonalDictionary()
        for (index, item) in terms.enumerated() {
            let created = now.addingTimeInterval(-Double((20 - index) * 86_400))
            dictionary.entries.append(
                PersonalDictionary.Entry(
                    id: UUID(),
                    term: item.0,
                    aliases: item.1,
                    category: item.2,
                    source: .manual,
                    createdAt: created,
                    updatedAt: created.addingTimeInterval(3600),
                    usageCount: item.3
                )
            )
        }
        store.setPersonalDictionary(dictionary)
    }
}
