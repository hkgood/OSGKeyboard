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
    }
}

#if DEBUG
#Preview("ThemedRoot · Dark") {
    ThemedRoot {
        ZStack {
            Palette.dark.background.ignoresSafeArea()
            Text("Dark")
                .foregroundStyle(Palette.dark.textPrimary)
                .font(.title)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("ThemedRoot · Light") {
    ThemedRoot {
        ZStack {
            Palette.light.background.ignoresSafeArea()
            Text("Light")
                .foregroundStyle(Palette.light.textPrimary)
                .font(.title)
        }
    }
    .preferredColorScheme(.light)
}
#endif