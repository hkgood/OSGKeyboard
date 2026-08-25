// HomeUsageStatsSection.swift
// OSGKeyboard · Main App
//
// Observes usage + dictionary counts and feeds the shared
// `UsageStatsCluster` (phone stacked / iPad split). Optional `header`
// (e.g. glass preview field) sits on the monthly calendar card.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

struct HomeUsageStatsSection<Header: View>: View {
    let layout: UsageStatsClusterLayout
    var compact: Bool = false
    var content: UsageStatsClusterContent = .all
    var onOpenHistory: (() -> Void)?
    var onOpenDictionary: (() -> Void)?
    @ViewBuilder var header: () -> Header

    @ObservedObject private var stats = UsageStatisticsStore.shared
    @ObservedObject private var config = ProviderConfig.shared

    @State private var dictionaryCount = 0

    var body: some View {
        UsageStatsCluster(
            layout: layout,
            language: config.uiLanguage,
            points: stats.currentMonth,
            dictationCharacterCount: stats.dictationCharacterCount,
            dictationDurationSeconds: stats.dictationDurationSeconds,
            translationCharacterCount: stats.translationCharacterCount,
            dictionaryTermCount: dictionaryCount,
            compact: compact,
            content: content,
            onOpenHistory: onOpenHistory,
            onOpenDictionary: onOpenDictionary,
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
    init(
        layout: UsageStatsClusterLayout,
        compact: Bool = false,
        content: UsageStatsClusterContent = .all,
        onOpenHistory: (() -> Void)? = nil,
        onOpenDictionary: (() -> Void)? = nil
    ) {
        self.init(
            layout: layout,
            compact: compact,
            content: content,
            onOpenHistory: onOpenHistory,
            onOpenDictionary: onOpenDictionary,
            header: { EmptyView() }
        )
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
