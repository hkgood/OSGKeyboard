// MacTheme.swift
// OSGKeyboard · Mac
//
// System-native colour palette for the desktop app. Instead of the custom
// near-black brand palette, the Mac app maps every design token onto AppKit
// semantic colours (`Color(nsColor:)`), which adapt to light / dark on their
// own. The brand green is kept only as the accent. This gives the app the
// same zero-colour-difference, System-Settings / Notes look on both
// appearances while reusing every existing `palette.X` call site.

import AppKit
import SwiftUI

enum MacSystemPalette {
    /// A `ThemePalette` whose surfaces and text resolve to AppKit semantic
    /// colours. Because those colours are dynamic, a single value renders
    /// correctly under both light and dark (driven by `preferredColorScheme`).
    static let palette = ThemePalette(
        background:      Color(nsColor: .windowBackgroundColor),
        surface:         Color(nsColor: .controlBackgroundColor),
        surfaceElevated: Color(nsColor: .unemphasizedSelectedContentBackgroundColor),
        surfaceMuted:    Color(nsColor: .underPageBackgroundColor),

        accent:          Palette.accent,
        accentMuted:     Palette.accent.opacity(0.16),
        accentGlow:      Palette.accent.opacity(0.35),

        danger:          Color(nsColor: .systemRed),
        success:         Palette.accent,
        warning:         Color(nsColor: .systemOrange),

        textPrimary:     Color(nsColor: .labelColor),
        textSecondary:   Color(nsColor: .secondaryLabelColor),
        textTertiary:    Color(nsColor: .tertiaryLabelColor),
        textOnAccent:    Color.white,

        divider:         Color(nsColor: .separatorColor),
        dividerStrong:   Color(nsColor: .separatorColor),

        recordRed:       Color(nsColor: .systemRed)
    )
}

extension View {
    /// Injects the system-native palette used across the macOS app.
    func macSystemPalette() -> some View {
        environment(\.themePalette, MacSystemPalette.palette)
    }
}
