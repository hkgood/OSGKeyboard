// WideLayoutComponents.swift
// OSGKeyboard · Main App
//
// Reusable layout pieces for iPad / regular-width surfaces. Styled with the
// shared design tokens so the wide Home dashboard can mirror the macOS shell
// without pulling in AppKit-only types from OSGKeyboardMac.
//
// Home stats (chart + metric tiles) live in Shared as `UsageStatsCluster`.

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
            .overlay(
                shape.stroke(palette.divider, lineWidth: 0.5)
            )
    }
}
