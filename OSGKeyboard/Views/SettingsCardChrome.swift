// SettingsCardChrome.swift
// OSGKeyboard · Main App
//
// Shared rounded surface chrome for settings list cards.

import SwiftUI
import OSGKeyboardShared

struct SettingsSurfaceCardModifier: ViewModifier {
    @Environment(\.themePalette) private var palette: ThemePalette

    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .stroke(palette.divider, lineWidth: 0.5)
                )
        } else {
            content
        }
    }
}
