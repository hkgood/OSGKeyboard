// UsageSurfaceCard.swift
// OSGKeyboard · Shared
//
// Semantic surface used by home / dashboard stats on every platform.
// Shared card elevation keeps its depth consistent with the rest of the app.

import SwiftUI

public struct UsageSurfaceCard<Content: View>: View {
    @Environment(\.themePalette) private var palette

    public var padding: CGFloat
    public var cornerRadius: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(
        padding: CGFloat = Spacing.md,
        cornerRadius: CGFloat = Radius.xl,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .padding(padding)
            .background(palette.surface, in: shape)
            .clipShape(shape)
            .cardElevation()
    }
}
