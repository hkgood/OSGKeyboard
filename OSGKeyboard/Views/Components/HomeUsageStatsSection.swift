// HomeUsageStatsSection.swift
// OSGKeyboard · Main App
//
// Observes usage + dictionary counts and feeds the shared
// `UsageStatsCluster` (phone stacked / iPad split).

import SwiftUI
import OSGKeyboardShared

struct HomeUsageStatsSection: View {
    let layout: UsageStatsCluster.Layout
    var compact: Bool = false

    @ObservedObject private var stats = UsageStatisticsStore.shared
    @ObservedObject private var config = ProviderConfig.shared

    @State private var dictionaryCount = 0

    var body: some View {
        UsageStatsCluster(
            layout: layout,
            language: config.uiLanguage,
            points: stats.last7Days,
            dictationCharacterCount: stats.dictationCharacterCount,
            dictationDurationSeconds: stats.dictationDurationSeconds,
            translationCharacterCount: stats.translationCharacterCount,
            dictionaryTermCount: dictionaryCount,
            compact: compact
        )
        .onAppear(perform: refreshDictionaryCount)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshDictionaryCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
            refreshDictionaryCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .usageStatisticsDidSyncFromCloud)) { _ in
            stats.reloadFromDisk()
        }
    }

    private func refreshDictionaryCount() {
        dictionaryCount = AppGroupStore().personalDictionary.entries.count
    }
}

#if DEBUG
#Preview("Phone stacked") {
    ThemedRoot {
        HomeUsageStatsSection(layout: .stacked)
            .padding()
    }
}

#Preview("Wide split") {
    ThemedRoot {
        HomeUsageStatsSection(layout: .split)
            .padding()
    }
}
#endif
