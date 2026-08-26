// MacTheme.swift
// OSGKeyboard · Mac
//
// System-native colour palette for the desktop app. Instead of the custom
// near-black brand palette, the Mac app maps every design token onto AppKit
// semantic colours, resolved to a concrete value for the *active* appearance.
// The brand green is kept only as the accent. Light mode uses a warm,
// iOS-matched surface set (the default `windowBackgroundColor` reads cold
// grey on macOS); Dark mode uses stepped elevated greys so cards stay
// readable against the page background.

import AppKit
import SwiftUI

enum MacSystemPalette {
    /// Returns the palette for the given colour scheme. Because the two
    /// palettes hold *concrete* (already-resolved) colours, the value changes
    /// identity when the scheme flips — so injecting it via `@Environment`
    /// (see `macSystemPalette()`) reliably re-renders every dependent view the
    /// instant the appearance changes, instead of lagging until the next
    /// view rebuild.
    static func palette(for scheme: ColorScheme) -> ThemePalette {
        scheme == .dark ? darkPalette : lightPalette
    }

    private static let lightPalette = makePalette(dark: false)
    private static let darkPalette = makePalette(dark: true)

    private static func makePalette(dark: Bool) -> ThemePalette {
        ThemePalette(
            background: resolved(dark ? darkBackground : warmBackground, dark: dark),
            surface: resolved(dark ? darkSurface : warmSurface, dark: dark),
            formSurface: resolved(dark ? darkFormSurface : warmFormSurface, dark: dark),
            surfaceElevated: resolved(dark ? darkElevated : warmElevated, dark: dark),
            surfaceMuted: resolved(dark ? darkMuted : warmMuted, dark: dark),

            accent: Palette.accent,
            accentMuted: Palette.accent.opacity(dark ? 0.22 : 0.14),
            accentGlow: Palette.accent.opacity(dark ? 0.40 : 0.32),
            aiTeal: Palette.aiTeal,

            danger: resolved(.systemRed, dark: dark),
            success: Palette.accent,
            warning: resolved(.systemOrange, dark: dark),

            textPrimary: resolved(.labelColor, dark: dark),
            textSecondary: resolved(.secondaryLabelColor, dark: dark),
            textTertiary: resolved(.tertiaryLabelColor, dark: dark),
            textOnAccent: OSGColor.fixedLightContent,

            divider: dark
                ? OSGColor.macDarkDivider
                : OSGColor.lightDivider,
            dividerStrong: dark
                ? OSGColor.macDarkDividerStrong
                : OSGColor.lightDividerStrong,

            recordRed: resolved(.systemRed, dark: dark),
            recordBlue: resolved(.systemBlue, dark: dark)
        )
    }

    // MARK: - Warm Light-mode surfaces (matched to iOS `Palette.light`)

    /// #F2F1EE — warm gray page background.
    private static let warmBackground = NSColor(OSGColor.lightBackground)
    /// #FCFBF9 — warm off-white card/control surface.
    private static let warmSurface = NSColor(OSGColor.lightSurface)
    /// #FCFBF9 — forms retain the ordinary card fill in light mode.
    private static let warmFormSurface = warmSurface
    /// #EBEAE7 — slightly recessed elevated surface.
    private static let warmElevated = NSColor(OSGColor.lightSurfaceElevated)
    /// #EEEDE9 — muted fill between background and surface.
    private static let warmMuted = NSColor(OSGColor.lightSurfaceMuted)

    // MARK: - Dark-mode surfaces (Apple standard elevated grays)
    //
    // AppKit's `controlBackgroundColor` is *darker* than `windowBackgroundColor`
    // in Dark Aqua, so cards using it recede into the page. Instead we step the
    // surfaces explicitly (systemGray6→4 equivalents) so every card reads as
    // clearly elevated above the background — mirroring the iOS dark palette.

    /// #1C1C1E — page background.
    private static let darkBackground = NSColor(OSGColor.macDarkBackground)
    /// #2C2C2E — card / control surface, clearly lighter than the background.
    private static let darkSurface = NSColor(OSGColor.macDarkSurface)
    /// #343438 — interactive form fill between cards and elevated chrome.
    private static let darkFormSurface = NSColor(OSGColor.macDarkFormSurface)
    /// #3A3A3C — elevated fill for selected / raised chrome.
    private static let darkElevated = NSColor(OSGColor.macDarkSurfaceElevated)
    /// #242426 — muted fill between background and surface.
    private static let darkMuted = NSColor(OSGColor.macDarkSurfaceMuted)

    /// Resolves a (possibly dynamic) AppKit colour to its concrete value under
    /// the requested appearance, so the two static palettes differ by value.
    private static func resolved(_ nsColor: NSColor, dark: Bool) -> Color {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else {
            return Color(nsColor: nsColor)
        }
        var result = nsColor
        appearance.performAsCurrentDrawingAppearance {
            result = nsColor.usingColorSpace(.sRGB) ?? nsColor
        }
        return Color(nsColor: result)
    }
}

private struct MacSystemPaletteModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.themePalette, MacSystemPalette.palette(for: colorScheme))
    }
}

extension View {
    /// Injects the system-native palette used across the macOS app, refreshed
    /// automatically whenever the effective colour scheme changes.
    func macSystemPalette() -> some View {
        modifier(MacSystemPaletteModifier())
    }
}
