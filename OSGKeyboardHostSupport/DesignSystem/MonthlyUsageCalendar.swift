// MonthlyUsageCalendar.swift
// OSGKeyboard · HostSupport
//
// Current-month dictation heat map. Every date remains visible; the monochrome
// circle's opacity communicates that day's character count relative to the
// busiest day in the same month.

import SwiftUI
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

public struct MonthlyUsageCalendar: View {
    @Environment(\.themePalette) private var palette

    public let points: [UsageStatisticsStore.DailyUsagePoint]
    public let language: AppUILanguage
    public var compact: Bool
    public var embedsInCard: Bool

    public init(
        points: [UsageStatisticsStore.DailyUsagePoint],
        language: AppUILanguage,
        compact: Bool = false,
        embedsInCard: Bool = true
    ) {
        self.points = points
        self.language = language
        self.compact = compact
        self.embedsInCard = embedsInCard
    }

    private var displayLocale: Locale {
        Locale(identifier: language.resolvedLanguageCode())
    }

    private var displayCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = displayLocale
        return calendar
    }

    private var total: Int {
        points.reduce(0) { $0 + $1.value }
    }

    private var maximumValue: Int {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var monthTitle: String {
        guard let date = points.first?.date else { return "" }
        return date.formatted(
            .dateTime
                .year()
                .month(.wide)
                .locale(displayLocale)
        )
    }

    private var weekdaySymbols: [String] {
        let symbols = displayCalendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(0, min(displayCalendar.firstWeekday - 1, symbols.count - 1))
        return Array(symbols[startIndex...] + symbols[..<startIndex])
    }

    private var leadingEmptyCellCount: Int {
        guard let firstDate = points.first?.date else { return 0 }
        let weekday = displayCalendar.component(.weekday, from: firstDate)
        return (weekday - displayCalendar.firstWeekday + 7) % 7
    }

    private var calendarCells: [UsageStatisticsStore.DailyUsagePoint?] {
        Array(repeating: nil, count: leadingEmptyCellCount) + points.map(Optional.some)
    }

    private var cellDiameter: CGFloat {
        #if os(macOS)
        // Mac 端收紧圆点直径，让左侧日历与右侧 2×2 网格高度接近。
        compact ? 26 : 28
        #else
        compact ? 28 : 32
        #endif
    }

    /// 日期网格的行间距（Mac 端更紧凑）。
    private var dayRowSpacing: CGFloat {
        #if os(macOS)
        compact ? 2 : 3
        #else
        compact ? 3 : 5
        #endif
    }

    /// 卡片内各区块（标题 / 星期 / 日期网格）的垂直间距。
    private var sectionSpacing: CGFloat {
        #if os(macOS)
        Spacing.xs
        #else
        Spacing.sm
        #endif
    }

    public var body: some View {
        Group {
            if embedsInCard {
                UsageSurfaceCard(padding: Spacing.md) {
                    calendarContent
                }
            } else {
                calendarContent
            }
        }
    }

    private var calendarContent: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            header
            weekdayHeader
            dayGrid
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(monthTitle.uppercased())
                    .font(TypeStyle.caption2)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(SharedL10n.string("stat.monthChart.caption", language: language))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Spacing.sm)
            Text(UsageStatisticsStore.formatCount(total, language: language))
                .font(TypeStyle.title2)
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Motion.soft, value: total)
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: columns, spacing: dayRowSpacing) {
            ForEach(Array(calendarCells.enumerated()), id: \.offset) { _, point in
                if let point {
                    dayCell(point)
                } else {
                    Color.clear
                        .frame(width: cellDiameter, height: cellDiameter)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: cellDiameter), spacing: 4),
            count: 7
        )
    }

    private func dayCell(_ point: UsageStatisticsStore.DailyUsagePoint) -> some View {
        let calendar = displayCalendar
        let day = calendar.component(.day, from: point.date)
        let isToday = calendar.isDateInToday(point.date)
        let isFuture = calendar.startOfDay(for: point.date) > calendar.startOfDay(for: Date())
        let opacity = fillOpacity(for: point.value, isFuture: isFuture)
        let usesContrastingText = opacity >= 0.48

        return Text(day.formatted())
            .font(.system(size: dayFontSize, weight: isToday ? .semibold : .medium, design: .rounded))
            .foregroundStyle(
                isFuture
                    ? palette.textTertiary.opacity(0.45)
                    : (usesContrastingText ? palette.background : palette.textPrimary)
            )
            .frame(width: cellDiameter, height: cellDiameter)
            .background(palette.textPrimary.opacity(opacity), in: Circle())
            .overlay {
                if isToday {
                    Circle()
                        .stroke(palette.textPrimary, lineWidth: 1.5)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement()
            .accessibilityLabel(
                Text(point.date.formatted(.dateTime.month().day()))
            )
            .accessibilityValue(
                Text(UsageStatisticsStore.formatCount(point.value, language: language))
            )
    }

    private var dayFontSize: CGFloat {
        #if os(macOS)
        compact ? 11 : 12
        #else
        compact ? 12 : 13
        #endif
    }

    private func fillOpacity(for value: Int, isFuture: Bool) -> Double {
        guard value > 0, !isFuture else { return 0 }
        let ratio = min(max(Double(value) / Double(maximumValue), 0), 1)
        return 0.05 + pow(ratio, 1.15) * 0.73
    }
}

#Preview("Monthly usage") {
    let calendar = Calendar.current
    let start = calendar.date(
        from: calendar.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    let points = (0..<31).compactMap { offset -> UsageStatisticsStore.DailyUsagePoint? in
        guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
            return nil
        }
        let value = offset.isMultiple(of: 5) ? offset * 120 : 0
        return UsageStatisticsStore.DailyUsagePoint(date: date, value: value)
    }

    ThemedRoot {
        MonthlyUsageCalendar(
            points: points,
            language: .auto
        )
        .padding()
    }
}
