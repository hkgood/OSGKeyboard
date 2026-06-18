// ThemedRoot.swift
// OSGKeyboard · Design System
//
// `ThemedRoot` injects the right `ThemePalette` for the current system
// colour scheme. Wrap the main App's root in this view to opt into
// light/dark following; the keyboard extension deliberately stays dark
// (Apple's custom keyboards always render dark) and does NOT use this.

import SwiftUI

public struct ThemedRoot<Content: View>: View {

    @Environment(\.colorScheme) private var colorScheme

    let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .environment(\.themePalette, colorScheme == .dark ? Palette.dark : Palette.light)
            .background(colorScheme == .dark ? Palette.dark.background : Palette.light.background)
    }
}

#if DEBUG
#Preview("ThemedRoot · Dark") {
    ThemedRoot {
        ThemedPreviewContent(title: "Dark")
    }
    .preferredColorScheme(.dark)
}

#Preview("ThemedRoot · Light") {
    ThemedRoot {
        ThemedPreviewContent(title: "Light")
    }
    .preferredColorScheme(.light)
}

private struct ThemedPreviewContent: View {
    @Environment(\.themePalette) private var palette
    let title: String

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            Text(title)
                .foregroundStyle(palette.textPrimary)
                .font(.title)
        }
    }
}
#endif
