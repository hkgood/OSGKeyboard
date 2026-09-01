// UsageStatsCluster.swift
// OSGKeyboard · HostSupport
//
// Cross-platform home / dashboard stats: monthly calendar + cumulative metrics.
// Callers observe their store and pass plain values — Shared stays unbound
// from platform singletons.
//
// Optional `header` sits above the monthly calendar inside the same surface card
// (iOS Home glass preview field). Mac / plain call sites keep `EmptyView`.

import SwiftUI
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

public enum UsageStatsClusterLayout: Sendable, Equatable {
    /// Monthly calendar left, 2×2 `UsageStatCard` grid right (Mac / iPad).
    case split
    /// Monthly calendar above a compact single-card 2×2 grid (iPhone).
    case stacked

    /// 手机端 2×2 统计网格的紧凑固定高度（沿用旧版 HomeStatsCard 数值）。
    public static let compactGridHeight: CGFloat = 166
}

public enum UsageStatsClusterContent: Sendable, Equatable {
    case all
    case calendar
    case metrics
}

public struct UsageStatsCluster<Header: View>: View {
    @Environment(\.themePalette) private var palette

    public let layout: UsageStatsClusterLayout
    public let language: AppUILanguage
    public let points: [UsageStatisticsStore.DailyUsagePoint]
    public let dictationCharacterCount: Int
    public let dictationDurationSeconds: TimeInterval
    public let translationCharacterCount: Int
    public let dictionaryTermCount: Int
    /// 小屏（如 iPhone SE）收紧日期圆形尺寸，把空间让给下方内容。
    public let compact: Bool
    public let content: UsageStatsClusterContent
    private let header: Header
    private let onOpenHistory: (() -> Void)?
    private let onOpenDictionary: (() -> Void)?

    public init(
        layout: UsageStatsClusterLayout,
        language: AppUILanguage,
        points: [UsageStatisticsStore.DailyUsagePoint],
        dictationCharacterCount: Int,
        dictationDurationSeconds: TimeInterval,
        translationCharacterCount: Int,
        dictionaryTermCount: Int,
        compact: Bool = false,
        content: UsageStatsClusterContent = .all,
        onOpenHistory: (() -> Void)? = nil,
        onOpenDictionary: (() -> Void)? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.layout = layout
        self.language = language
        self.points = points
        self.dictationCharacterCount = dictationCharacterCount
        self.dictationDurationSeconds = dictationDurationSeconds
        self.translationCharacterCount = translationCharacterCount
        self.dictionaryTermCount = dictionaryTermCount
        self.compact = compact
        self.content = content
        self.onOpenHistory = onOpenHistory
        self.onOpenDictionary = onOpenDictionary
        self.header = header()
    }

    @ViewBuilder
    public var body: some View {
        switch content {
        case .all:
            switch layout {
            case .split:
                splitBody
            case .stacked:
                stackedBody
            }
        case .calendar:
            chartCard
        case .metrics:
            metricsBody
        }
    }

    // MARK: - Split (Mac / iPad)

    private var splitBody: some View {
        HStack(alignment: .top, spacing: splitSectionSpacing) {
            chartCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            splitStatGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var splitStatGrid: some View {
        VStack(spacing: splitItemSpacing) {
            HStack(spacing: splitItemSpacing) {
                splitCell(
                    title: SharedL10n.string("stat.words", language: language),
                    value: UsageStatisticsStore.formatCount(dictationCharacterCount, language: language),
                    caption: SharedL10n.string("stat.transcribed", language: language),
                    systemImage: "text.alignleft",
                    accent: true,
                    action: onOpenHistory
                )
                splitCell(
                    title: SharedL10n.string("stat.dictationTime", language: language),
                    value: UsageStatisticsStore.formatDuration(dictationDurationSeconds, language: language),
                    caption: SharedL10n.string("stat.cumulativeDuration", language: language),
                    systemImage: "waveform"
                )
            }
            .frame(maxHeight: splitRowMaxHeight)
            HStack(spacing: splitItemSpacing) {
                splitCell(
                    title: SharedL10n.string("stat.translation", language: language),
                    value: UsageStatisticsStore.formatCount(translationCharacterCount, language: language),
                    caption: SharedL10n.string("stat.cumulativeTranslation", language: language),
                    systemImage: "character.bubble"
                )
                splitCell(
                    title: SharedL10n.string("stat.dictionary", language: language),
                    value: UsageStatisticsStore.formatCount(dictionaryTermCount, language: language),
                    caption: SharedL10n.string("stat.customTerms", language: language),
                    systemImage: "character.book.closed",
                    action: onOpenDictionary
                )
            }
            .frame(maxHeight: splitRowMaxHeight)
        }
    }

    @ViewBuilder
    private var metricsBody: some View {
        switch layout {
        case .split:
            splitStatGrid
        case .stacked:
            compactStatGrid
        }
    }

    @ViewBuilder
    private func splitCell(
        title: String,
        value: String,
        caption: String,
        systemImage: String,
        accent: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action {
            Button(action: action) {
                UsageStatCard(
                    title: title,
                    value: value,
                    caption: caption,
                    accent: accent,
                    expands: splitCellsFillHeight
                )
                .overlay(alignment: .topTrailing) {
                    disclosureIndicator
                        .padding(Spacing.md)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: splitRowMaxHeight)
        } else {
            UsageStatCard(
                title: title,
                value: value,
                caption: caption,
                systemImage: systemImage,
                accent: accent,
                expands: splitCellsFillHeight
            )
            .frame(maxHeight: splitRowMaxHeight)
        }
    }

    // MARK: - Stacked (iPhone)

    private var stackedBody: some View {
        VStack(spacing: CardLayoutMetrics.sectionSpacing) {
            chartCard
            compactStatGrid
        }
    }

    /// Calendar surface; when `header` is present it sits above the dates in the same card.
    @ViewBuilder
    private var chartCard: some View {
        if Header.self == EmptyView.self {
            MonthlyUsageCalendar(
                points: points,
                language: language,
                compact: compact
            )
        } else {
            UsageSurfaceCard(padding: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    header
                    MonthlyUsageCalendar(
                        points: points,
                        language: language,
                        compact: compact,
                        embedsInCard: false
                    )
                }
            }
        }
    }

    /// Phone-friendly 2×2: each metric has its own compact surface card.
    private var compactStatGrid: some View {
        VStack(spacing: CardLayoutMetrics.compactItemSpacing) {
            HStack(spacing: CardLayoutMetrics.compactItemSpacing) {
                compactCell(
                    systemImage: "timer",
                    value: UsageStatisticsStore.formatDuration(dictationDurationSeconds, language: language),
                    label: SharedL10n.string("stat.dictationTime", language: language)
                )
                compactCell(
                    systemImage: "quote.bubble",
                    value: UsageStatisticsStore.formatCount(dictationCharacterCount, language: language),
                    label: SharedL10n.string("stat.words", language: language),
                    action: onOpenHistory
                )
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: CardLayoutMetrics.compactItemSpacing) {
                compactCell(
                    systemImage: "translate",
                    value: UsageStatisticsStore.formatCount(translationCharacterCount, language: language),
                    label: SharedL10n.string("stat.translation", language: language)
                )
                compactCell(
                    systemImage: "book.pages",
                    value: UsageStatisticsStore.formatCount(dictionaryTermCount, language: language),
                    label: SharedL10n.string("stat.dictionary", language: language),
                    action: onOpenDictionary
                )
            }
            .frame(maxHeight: .infinity)
        }
        // 锁定紧凑固定高度（对齐旧版 HomeStatsCard 的 166pt），避免格子按内容撑高。
        .frame(height: UsageStatsClusterLayout.compactGridHeight)
    }

    @ViewBuilder
    private func compactCell(
        systemImage: String,
        value: String,
        label: String,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action {
            Button(action: action) {
                compactCellContent(
                    systemImage: systemImage,
                    value: value,
                    label: label,
                    showsDisclosure: true
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            compactCellContent(
                systemImage: systemImage,
                value: value,
                label: label,
                showsDisclosure: false
            )
        }
    }

    private func compactCellContent(
        systemImage: String,
        value: String,
        label: String,
        showsDisclosure: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
            // Subtle watermark stays fully visible within the card edges.
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .ultraLight))
                .foregroundStyle(palette.textPrimary.opacity(0.10))
                .frame(width: 44, height: 44, alignment: .center)
                .offset(x: Spacing.xs, y: Spacing.xs)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Spacing.sm)
        .background(palette.surface, in: shape)
        .overlay(alignment: .topTrailing) {
            if showsDisclosure {
                disclosureIndicator
                    .padding(Spacing.sm)
            }
        }
        .clipShape(shape)
        .cardElevation()
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(palette.textTertiary)
            .accessibilityHidden(true)
    }

    private var splitSectionSpacing: CGFloat {
        #if os(macOS)
        Spacing.sm
        #else
        CardLayoutMetrics.sectionSpacing
        #endif
    }

    private var splitItemSpacing: CGFloat {
        #if os(macOS)
        Spacing.sm
        #else
        CardLayoutMetrics.compactItemSpacing
        #endif
    }

    private var splitRowMaxHeight: CGFloat? {
        splitCellsFillHeight ? .infinity : nil
    }

    /// Mac 侧的 2×2 网格拉伸到与左侧日历同高，保证左右卡片底边对齐。
    private var splitCellsFillHeight: Bool {
        #if os(macOS)
        layout == .split
        #else
        false
        #endif
    }
}

extension UsageStatsCluster where Header == EmptyView {
    public init(
        layout: UsageStatsClusterLayout,
        language: AppUILanguage,
        points: [UsageStatisticsStore.DailyUsagePoint],
        dictationCharacterCount: Int,
        dictationDurationSeconds: TimeInterval,
        translationCharacterCount: Int,
        dictionaryTermCount: Int,
        compact: Bool = false,
        content: UsageStatsClusterContent = .all,
        onOpenHistory: (() -> Void)? = nil,
        onOpenDictionary: (() -> Void)? = nil
    ) {
        self.init(
            layout: layout,
            language: language,
            points: points,
            dictationCharacterCount: dictationCharacterCount,
            dictationDurationSeconds: dictationDurationSeconds,
            translationCharacterCount: translationCharacterCount,
            dictionaryTermCount: dictionaryTermCount,
            compact: compact,
            content: content,
            onOpenHistory: onOpenHistory,
            onOpenDictionary: onOpenDictionary,
            header: { EmptyView() }
        )
    }
}
