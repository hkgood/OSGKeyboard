// UsageStatCard.swift
// OSGKeyboard · Shared
//
// Single cumulative metric tile. Compact = title / value / caption stack;
// prominent = horizontal hero bar for the primary word-count metric.

import SwiftUI

public struct UsageStatCard: View {
    @Environment(\.themePalette) private var palette

    public let title: String
    public let value: String
    public let caption: String
    public var systemImage: String?
    public var accent: Bool
    /// Hero metric: wide horizontal layout for the primary word count.
    public var prominent: Bool

    public init(
        title: String,
        value: String,
        caption: String,
        systemImage: String? = nil,
        accent: Bool = false,
        prominent: Bool = false
    ) {
        self.title = title
        self.value = value
        self.caption = caption
        self.systemImage = systemImage
        self.accent = accent
        self.prominent = prominent
    }

    public var body: some View {
        UsageSurfaceCard(padding: Spacing.md) {
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

    /// Wide "hero bar": icon badge + title/caption left, big number right.
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
