// SevenDayUsageChart.swift
// OSGKeyboard · Shared
//
// 7-day dictation bar chart. Platform shells wrap this in their own page
// layout; the chart itself only needs points + UI language.

import Charts
import SwiftUI

public struct SevenDayUsageChart: View {
    @Environment(\.themePalette) private var palette

    public let points: [UsageStatisticsStore.DailyUsagePoint]
    public let language: AppUILanguage
    /// Bar area height. Phone stacked layout uses a shorter value.
    public var chartMinHeight: CGFloat
    /// When true, wrap content in `UsageSurfaceCard` (default). Pass false if
    /// the caller already provides a surface.
    public var embedsInCard: Bool
    /// When true (iPad split), the chart fills all available height. When false
    /// (phone stacked home), the bar area is a fixed `chartMinHeight` so the card
    /// stays compact and does not steal space from surrounding content.
    public var expands: Bool

    public init(
        points: [UsageStatisticsStore.DailyUsagePoint],
        language: AppUILanguage,
        chartMinHeight: CGFloat = 96,
        embedsInCard: Bool = true,
        expands: Bool = true
    ) {
        self.points = points
        self.language = language
        self.chartMinHeight = chartMinHeight
        self.embedsInCard = embedsInCard
        self.expands = expands
    }

    private var total: Int {
        points.reduce(0) { $0 + $1.value }
    }

    private var maxValue: Int {
        max(points.map(\.value).max() ?? 0, 1)
    }

    private var chartLocale: Locale {
        Locale(identifier: language.resolvedLanguageCode())
    }

    /// The real day for each bar; used to decide which axis marks get a label.
    private var pointDates: Set<Date> {
        Set(points.map(\.date))
    }

    /// Axis tick positions: the 7 real days plus one trailing boundary (last + 1
    /// day) so `centered: true` has a span to center the final day's label within.
    private var axisDates: [Date] {
        let dates = points.map(\.date)
        guard let last = dates.last,
              let boundary = Calendar.current.date(byAdding: .day, value: 1, to: last)
        else { return dates }
        return dates + [boundary]
    }

    public var body: some View {
        Group {
            if embedsInCard {
                UsageSurfaceCard(padding: Spacing.md) {
                    chartContent
                }
            } else {
                chartContent
            }
        }
    }

    private var chartContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            header
            chart
                .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil)
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: expands ? .infinity : nil,
            alignment: .topLeading
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SharedL10n.string("stat.weekChart.title", language: language).uppercased())
                    .font(TypeStyle.caption2)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(SharedL10n.string("stat.weekChart.caption", language: language))
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

    // MARK: - Bars

    @ViewBuilder
    private var chart: some View {
        if total == 0 {
            Text(SharedL10n.string("stat.weekChart.empty", language: language))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: expands ? .infinity : nil, alignment: .center)
                .multilineTextAlignment(.center)
                .frame(height: expands ? nil : chartMinHeight)
                .frame(minHeight: expands ? chartMinHeight : nil)
        } else {
            Chart(points) { point in
                BarMark(
                    x: .value("day", point.date, unit: .day),
                    y: .value("chars", point.value)
                )
                .cornerRadius(4)
                .foregroundStyle(palette.accent.gradient)
            }
            .chartYScale(domain: 0...max(1, Int(ceil(Double(maxValue) * 1.15))))
            .chartYAxis(.hidden)
            .chartXAxis {
                // Center each weekday label under its bar. Date `BarMark`s draw the
                // bar centered within its day band, but axis labels default to the
                // day's leading tick, so `centered: true` re-centers them on the bar.
                //
                // `centered` positions a label between its tick and the *next* tick,
                // so the final day (Saturday) would be dropped for lack of a trailing
                // tick. We append one boundary tick (last day + 1) to give it a span,
                // and only draw labels for the real 7 days.
                AxisMarks(values: axisDates) { value in
                    if let date = value.as(Date.self), pointDates.contains(date) {
                        AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                    }
                }
            }
            .environment(\.locale, chartLocale)
            .frame(height: expands ? nil : chartMinHeight)
            .frame(minHeight: expands ? chartMinHeight : nil)
        }
    }
}
