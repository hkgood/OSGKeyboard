// HomeStatsCard.swift
// OSGKeyboard · Main App
//
// Home screen summary: dictation time, dictation characters,
// translation characters, and personal-dictionary entry count.

import SwiftUI
import OSGKeyboardShared

struct HomeStatsCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject private var stats = UsageStatisticsStore.shared
    @ObservedObject private var config = ProviderConfig.shared

    @State private var dictionaryCount = 0

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
                    systemImage: "books.vertical",
                    value: UsageStatisticsStore.formatCount(
                        dictionaryCount,
                        language: config.uiLanguage
                    ),
                    label: "home.stats.dictionaryEntries"
                )
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
        .onAppear(perform: refreshDictionaryCount)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshDictionaryCount()
        }
    }

    private var cardBackground: some View {
        ZStack(alignment: .top) {
            palette.surface
            LinearGradient(
                colors: [
                    palette.accent.opacity(0.10),
                    palette.accent.opacity(0.02),
                    palette.surface.opacity(0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func statCell(systemImage: String, value: String, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text(value)
                    .font(TypeStyle.headline)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(label)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
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
}

#if DEBUG
#Preview {
    ThemedRoot {
        HomeStatsCard()
            .padding()
    }
}
#endif
