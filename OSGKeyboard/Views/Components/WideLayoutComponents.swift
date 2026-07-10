// WideLayoutComponents.swift
// OSGKeyboard · Main App
//
// Reusable layout pieces for iPad / regular-width surfaces. Styled with the
// shared design tokens so the wide Home dashboard can mirror the macOS shell
// without pulling in AppKit-only types from OSGKeyboardMac.

import SwiftUI
import OSGKeyboardShared

// MARK: - Layout metrics

/// Fixed metrics that keep wide surfaces on the same grid as the macOS app.
enum WideLayoutMetrics {
    static let sidebarWidth: CGFloat = 240
    static let sidebarInset: CGFloat = Spacing.md
    static let sidebarContentInset: CGFloat = sidebarInset + Spacing.sm
    static let pageHorizontalInset: CGFloat = 40
    static let dictationCanvasMinHeight: CGFloat = 120
}

// MARK: - Card container

/// Elevated surface used for stat tiles and the dictation canvas.
struct WideCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    var padding: CGFloat = Spacing.md
    var cornerRadius: CGFloat = Radius.medium
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .padding(padding)
            .background(palette.surface, in: shape)
            .overlay(
                shape.stroke(palette.divider, lineWidth: 0.5)
            )
    }
}

// MARK: - Stat tile

struct WideStatCard: View {
    @Environment(\.themePalette) private var palette
    let title: String
    let value: String
    let caption: String
    var systemImage: String?
    var accent: Bool = false
    /// Hero metric: wide horizontal layout for the primary word count.
    var prominent: Bool = false

    var body: some View {
        WideCard(padding: Spacing.md) {
            if prominent {
                prominentBody
            } else {
                compactBody
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title.uppercased())
                    .font(TypeStyle.caption2)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent ? palette.accent : palette.textTertiary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            Text(value)
                .font(TypeStyle.title2)
                .foregroundStyle(accent ? palette.accent : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Motion.soft, value: value)
            Text(caption)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var prominentBody: some View {
        HStack(spacing: Spacing.md) {
            if let systemImage {
                ZStack {
                    Circle()
                        .fill(palette.accentMuted)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(TypeStyle.caption2)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(caption)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Spacing.md)
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(accent ? palette.accent : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(Motion.soft, value: value)
        }
    }
}

// MARK: - Home stats cluster

/// Dashboard-style stat cluster for the wide Home layout.
struct WideHomeStatsCluster: View {
    @ObservedObject private var stats = UsageStatisticsStore.shared
    @ObservedObject private var config = ProviderConfig.shared

    @State private var dictionaryCount = 0

    private var language: AppUILanguage { config.uiLanguage }

    var body: some View {
        VStack(spacing: Spacing.md) {
            WideStatCard(
                title: AppL10n.string("home.stats.dictationCharacters", language: language),
                value: UsageStatisticsStore.formatCount(
                    stats.dictationCharacterCount,
                    language: language
                ),
                caption: AppL10n.string("home.wide.stat.transcribed", language: language),
                systemImage: "text.alignleft",
                accent: true,
                prominent: true
            )

            HStack(spacing: Spacing.md) {
                WideStatCard(
                    title: AppL10n.string("home.stats.dictationDuration", language: language),
                    value: UsageStatisticsStore.formatDuration(
                        stats.dictationDurationSeconds,
                        language: language
                    ),
                    caption: AppL10n.string("home.wide.stat.cumulativeDuration", language: language),
                    systemImage: "waveform"
                )
                WideStatCard(
                    title: AppL10n.string("home.stats.translationCharacters", language: language),
                    value: UsageStatisticsStore.formatCount(
                        stats.translationCharacterCount,
                        language: language
                    ),
                    caption: AppL10n.string("home.wide.stat.cumulativeTranslation", language: language),
                    systemImage: "character.bubble"
                )
                WideStatCard(
                    title: AppL10n.string("home.stats.dictionaryEntries", language: language),
                    value: UsageStatisticsStore.formatCount(
                        dictionaryCount,
                        language: language
                    ),
                    caption: AppL10n.string("home.wide.stat.customTerms", language: language),
                    systemImage: "character.book.closed"
                )
            }
        }
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
