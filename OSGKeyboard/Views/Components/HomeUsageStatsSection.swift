// HomeUsageStatsSection.swift
// OSGKeyboard · Main App
//
// Observes usage + dictionary counts and feeds the shared
// `UsageStatsCluster` (phone stacked / iPad split). Optional `header`
// (e.g. glass preview field) sits on the 7-day chart card.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

struct HomeUsageStatsSection<Header: View>: View {
    let layout: UsageStatsClusterLayout
    var compact: Bool = false
    @ViewBuilder var header: () -> Header

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
            compact: compact,
            header: header
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

extension HomeUsageStatsSection where Header == EmptyView {
    init(layout: UsageStatsClusterLayout, compact: Bool = false) {
        self.init(layout: layout, compact: compact, header: { EmptyView() })
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
