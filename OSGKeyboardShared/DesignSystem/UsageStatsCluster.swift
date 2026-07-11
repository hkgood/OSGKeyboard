// UsageStatsCluster.swift
// OSGKeyboard · Shared
//
// Cross-platform home / dashboard stats: 7-day chart + cumulative metrics.
// Callers observe their store and pass plain values — Shared stays unbound
// from platform singletons.

import SwiftUI

public struct UsageStatsCluster: View {
    @Environment(\.themePalette) private var palette

    public enum Layout: Sendable, Equatable {
        /// Chart left, 2×2 `UsageStatCard` grid right (Mac / iPad).
        case split
        /// Chart above a compact single-card 2×2 grid (iPhone).
        case stacked
    }

    /// 手机端 2×2 统计网格的紧凑固定高度（沿用旧版 HomeStatsCard 数值）。
    static let compactGridHeight: CGFloat = 166

    public let layout: Layout
    public let language: AppUILanguage
    public let points: [UsageStatisticsStore.DailyUsagePoint]
    public let dictationCharacterCount: Int
    public let dictationDurationSeconds: TimeInterval
    public let translationCharacterCount: Int
    public let dictionaryTermCount: Int
    /// 小屏（如 iPhone SE）收紧 stacked 图表高度，把空间让给下方的输入框。
    public let compact: Bool

    public init(
        layout: Layout,
        language: AppUILanguage,
        points: [UsageStatisticsStore.DailyUsagePoint],
        dictationCharacterCount: Int,
        dictationDurationSeconds: TimeInterval,
        translationCharacterCount: Int,
        dictionaryTermCount: Int,
        compact: Bool = false
    ) {
        self.layout = layout
        self.language = language
        self.points = points
        self.dictationCharacterCount = dictationCharacterCount
        self.dictationDurationSeconds = dictationDurationSeconds
        self.translationCharacterCount = translationCharacterCount
        self.dictionaryTermCount = dictionaryTermCount
        self.compact = compact
    }

    public var body: some View {
        switch layout {
        case .split:
            splitBody
        case .stacked:
            stackedBody
        }
    }

    // MARK: - Split (Mac / iPad)

    private var splitBody: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            SevenDayUsageChart(points: points, language: language)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            splitStatGrid
                .frame(maxWidth: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var splitStatGrid: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                UsageStatCard(
                    title: SharedL10n.string("stat.words", language: language),
                    value: UsageStatisticsStore.formatCount(dictationCharacterCount, language: language),
                    caption: SharedL10n.string("stat.transcribed", language: language),
                    systemImage: "text.alignleft",
                    accent: true
                )
                UsageStatCard(
                    title: SharedL10n.string("stat.dictationTime", language: language),
                    value: UsageStatisticsStore.formatDuration(dictationDurationSeconds, language: language),
                    caption: SharedL10n.string("stat.cumulativeDuration", language: language),
                    systemImage: "waveform"
                )
            }
            HStack(spacing: Spacing.md) {
                UsageStatCard(
                    title: SharedL10n.string("stat.translation", language: language),
                    value: UsageStatisticsStore.formatCount(translationCharacterCount, language: language),
                    caption: SharedL10n.string("stat.cumulativeTranslation", language: language),
                    systemImage: "character.bubble"
                )
                UsageStatCard(
                    title: SharedL10n.string("stat.dictionary", language: language),
                    value: UsageStatisticsStore.formatCount(dictionaryTermCount, language: language),
                    caption: SharedL10n.string("stat.customTerms", language: language),
                    systemImage: "character.book.closed"
                )
            }
        }
    }

    // MARK: - Stacked (iPhone)

    private var stackedBody: some View {
        VStack(spacing: compact ? Spacing.sm : Spacing.md) {
            SevenDayUsageChart(
                points: points,
                language: language,
                chartMinHeight: compact ? 72 : 96,
                expands: false
            )
            compactStatGrid
        }
    }

    /// Phone-friendly 2×2: value + label only, single card with hairline dividers.
    private var compactStatGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                compactCell(
                    systemImage: "waveform",
                    value: UsageStatisticsStore.formatDuration(dictationDurationSeconds, language: language),
                    label: SharedL10n.string("stat.dictationTime", language: language)
                )
                compactDivider
                compactCell(
                    systemImage: "text.alignleft",
                    value: UsageStatisticsStore.formatCount(dictationCharacterCount, language: language),
                    label: SharedL10n.string("stat.words", language: language)
                )
            }
            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)
            HStack(spacing: 0) {
                compactCell(
                    systemImage: "character.bubble",
                    value: UsageStatisticsStore.formatCount(translationCharacterCount, language: language),
                    label: SharedL10n.string("stat.translation", language: language)
                )
                compactDivider
                compactCell(
                    systemImage: "character.book.closed",
                    value: UsageStatisticsStore.formatCount(dictionaryTermCount, language: language),
                    label: SharedL10n.string("stat.dictionary", language: language)
                )
            }
        }
        // 锁定紧凑固定高度（对齐旧版 HomeStatsCard 的 166pt），避免格子按内容撑高。
        .frame(height: UsageStatsCluster.compactGridHeight)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private var compactDivider: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(width: 0.5)
    }

    private func compactCell(systemImage: String, value: String, label: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(.numericText())
                    .animation(Motion.soft, value: value)
                Text(label)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: Spacing.xs)
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
    }
}
