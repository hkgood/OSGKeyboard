// HomeStatsCard.swift
// OSGKeyboard · Main App
//
// Home screen summary: dictation time, dictation characters,
// translation characters, and personal-dictionary entry count.

import SwiftUI
import OSGKeyboardShared

struct HomeStatsCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var stats = UsageStatisticsStore.shared
    @ObservedObject private var config = ProviderConfig.shared

    @State private var dictionaryCount = 0

    private enum Layout {
        static let fixedHeight: CGFloat = 166
        static let valueFontSize: CGFloat = 24
        static let iconSize: CGFloat = 18
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statCell(
                    systemImage: "waveform",
                    value: UsageStatisticsStore.formatDuration(
                        stats.dictationDurationSeconds,
                        language: config.uiLanguage
                    ),
                    label: "home.stats.dictationDuration"
                )
                divider
                statCell(
                    systemImage: "text.alignleft",
                    value: UsageStatisticsStore.formatCount(
                        stats.dictationCharacterCount,
                        language: config.uiLanguage
                    ),
                    label: "home.stats.dictationCharacters"
                )
            }
            horizontalDivider
            HStack(spacing: 0) {
                statCell(
                    systemImage: "character.bubble",
                    value: UsageStatisticsStore.formatCount(
                        stats.translationCharacterCount,
                        language: config.uiLanguage
                    ),
                    label: "home.stats.translationCharacters"
                )
                divider
                statCell(
                    systemImage: "square.stack.3d.down.right.fill",
                    value: UsageStatisticsStore.formatCount(
                        dictionaryCount,
                        language: config.uiLanguage
                    ),
                    label: "home.stats.dictionaryEntries"
                )
            }
        }
        .frame(height: Layout.fixedHeight)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
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

    private func statCell(systemImage: String, value: String, label: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(value)
                    .font(.system(size: Layout.valueFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: Spacing.xs)
            Image(systemName: systemImage)
                .font(.system(size: Layout.iconSize, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(width: 0.5)
    }

    private var horizontalDivider: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(height: 0.5)
    }

    private func refreshDictionaryCount() {
        dictionaryCount = AppGroupStore().personalDictionary.entries.count
    }

    private var cardBackground: Color {
        colorScheme == .dark ? palette.surface : .white
    }
}

#if DEBUG
#Preview {
    ThemedRoot {
        HomeStatsCard()
            .padding()
    }
}
#endif
