// WideLayoutComponents.swift
// OSGKeyboard · Main App
//
// Reusable layout pieces for iPad / regular-width surfaces. Styled with the
// shared design tokens so the wide Home dashboard can mirror the macOS shell
// without pulling in AppKit-only types from OSGKeyboardMac.
//
// Home stats (chart + metric tiles) live in Shared as `UsageStatsCluster`.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

// MARK: - Layout metrics

/// Fixed metrics that keep wide surfaces on the same grid as the macOS app.
enum WideLayoutMetrics {
    static let sidebarWidth: CGFloat = 240
    static let sidebarInset: CGFloat = Spacing.md
    static let sidebarContentInset: CGFloat = sidebarInset + Spacing.sm
    static let pageHorizontalInset: CGFloat = 40
    static let dictationCanvasMinHeight: CGFloat = 120

    /// Wide pages keep at least this much room between the window's top edge
    /// and their content, so the first row clears the rounded display corner.
    static let minimumTopClearance: CGFloat = Spacing.md

    /// Extra top padding for wide pages. A status bar above the content
    /// (iPad, the portrait iPhone Duo inner display) already provides the
    /// room; the landscape inner display moves the status bar to the side and
    /// leaves a zero top safe area, so the content needs its own clearance.
    static func topCornerClearance(topSafeAreaInset: CGFloat) -> CGFloat {
        max(0, minimumTopClearance - topSafeAreaInset)
    }
}

extension EnvironmentValues {
    /// `WideLayoutMetrics.topCornerClearance` for the current window,
    /// published by `MainTabView`.
    @Entry var wideTopCornerClearance: CGFloat = 0
}

// MARK: - Card container

/// Elevated surface used for the dictation canvas on wide Home.
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
            .cardElevation()
    }
}
