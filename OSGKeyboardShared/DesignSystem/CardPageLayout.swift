// CardPageLayout.swift
// OSGKeyboard · Shared
//
// Shared structure for card-based pages: consistent page margins, section
// labels, and surface chrome while leaving each feature's content flexible.

import SwiftUI

public struct CardPageContent<Content: View>: View {
    private let spacing: CGFloat
    private let topPadding: CGFloat
    private let bottomPadding: CGFloat
    private let content: Content

    public init(
        spacing: CGFloat = Spacing.md,
        topPadding: CGFloat = Spacing.md,
        bottomPadding: CGFloat = Spacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.topPadding = topPadding
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
    }
}

public struct CardSection<Content: View>: View {
    private let title: Text
    private let content: Content

    public init(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(title)
        self.content = content()
    }

    public init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = Text(verbatim: title)
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            title
                .cardSectionLabel()
            content
        }
    }
}

public struct CardSectionLabelModifier: ViewModifier {
    @Environment(\.themePalette) private var palette

    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct SurfaceCardModifier: ViewModifier {
    @Environment(\.themePalette) private var palette

    private let enabled: Bool

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func body(content: Content) -> some View {
        if enabled {
            let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            content
                .background(
                    palette.surface,
                    in: shape
                )
                // Clip child backgrounds as well as the card surface. Without
                // this, a full-width child can visually square off a corner
                // even though the shared background and border use Radius.xl.
                .clipShape(shape)
                .overlay(
                    shape.stroke(palette.divider, lineWidth: 0.5)
                )
        } else {
            content
        }
    }
}

public extension View {
    func cardSectionLabel() -> some View {
        modifier(CardSectionLabelModifier())
    }

    func surfaceCard(enabled: Bool = true) -> some View {
        modifier(SurfaceCardModifier(enabled: enabled))
    }
}
