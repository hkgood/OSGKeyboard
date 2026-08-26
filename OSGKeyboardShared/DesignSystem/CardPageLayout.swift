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
        spacing: CGFloat = CardLayoutMetrics.sectionSpacing,
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
    private let elevated: Bool

    public init(enabled: Bool = true, elevated: Bool = true) {
        self.enabled = enabled
        self.elevated = elevated
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if enabled {
            let shape = RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            let card = content
                .background(
                    elevated ? palette.surface : palette.formSurface,
                    in: shape
                )
                // Clip child backgrounds as well as the card surface. Without
                // this, a full-width child can visually square off a corner.
                .clipShape(shape)
            if elevated {
                card.cardElevation()
            } else {
                card
            }
        } else {
            content
        }
    }
}

private struct CardElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let accented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        // Layered low-opacity shadows create direction and length without
        // turning the warm background gray.
        content
            .shadow(
                color: nearShadowColor,
                radius: 1,
                x: 2,
                y: 3
            )
            .shadow(
                color: midShadowColor,
                radius: 3,
                x: 6,
                y: 8
            )
            .shadow(
                color: farShadowColor,
                radius: 9,
                x: 12,
                y: 18
            )
        #else
        content
        #endif
    }

    private var nearShadowColor: Color {
        guard accented else { return OSGColor.cardShadowNear }
        return colorScheme == .dark
            ? OSGColor.selectedCardShadowNearDark
            : OSGColor.selectedCardShadowNearLight
    }

    private var midShadowColor: Color {
        guard accented else { return OSGColor.cardShadowMid }
        return colorScheme == .dark
            ? OSGColor.selectedCardShadowMidDark
            : OSGColor.selectedCardShadowMidLight
    }

    private var farShadowColor: Color {
        guard accented else { return OSGColor.cardShadowFar }
        return colorScheme == .dark
            ? OSGColor.selectedCardShadowFarDark
            : OSGColor.selectedCardShadowFarLight
    }
}

private struct CardListRowModifier: ViewModifier {
    let bottomSpacing: CGFloat
    let elevated: Bool

    func body(content: Content) -> some View {
        content
            .surfaceCard(elevated: elevated)
            .listRowInsets(
                EdgeInsets(
                    top: 0,
                    leading: 0,
                    bottom: bottomSpacing,
                    trailing: 0
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

public extension View {
    func cardSectionLabel() -> some View {
        modifier(CardSectionLabelModifier())
    }

    func surfaceCard(
        enabled: Bool = true,
        elevated: Bool = true
    ) -> some View {
        modifier(SurfaceCardModifier(enabled: enabled, elevated: elevated))
    }

    func cardElevation(accented: Bool = false) -> some View {
        modifier(CardElevationModifier(accented: accented))
    }

    /// Makes a native List/Form row render as an elevated app card while
    /// retaining system scrolling, swipe actions, refresh, and keyboard logic.
    func cardListRow(
        bottomSpacing: CGFloat = 0,
        elevated: Bool = true
    ) -> some View {
        modifier(CardListRowModifier(bottomSpacing: bottomSpacing, elevated: elevated))
    }
}
