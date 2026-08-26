// ColorLibrary.swift
// OSGKeyboard · Shared Design System
//
// Canonical custom colour values used across the app, keyboard extension,
// previews, and platform chrome. Views should prefer semantic ThemePalette
// roles; use these fixed tokens only when a surface intentionally does not
// follow the active app appearance.

import SwiftUI

public enum OSGColor {
    // MARK: - Brand

    public static let brandAccent = color(0x3AA05A)
    public static let aiTeal = color(0x2BAFA4)
    /// Content that must remain white on colored or generated artwork.
    public static let fixedLightContent = Color.white
    public static let fixedDarkContent = Color.black

    // MARK: - iOS app theme

    public static let darkBackground = color(0x0A0A0B)
    public static let darkSurface = color(0x18181B)
    /// Interactive form fill: lighter than cards without looking elevated.
    public static let darkFormSurface = color(0x202024)
    public static let darkSurfaceElevated = color(0x27272A)
    public static let darkSurfaceMuted = color(0x121215)
    public static let darkDanger = color(0xFF453A)
    public static let darkWarning = color(0xFFBF18)
    public static let darkTextPrimary = color(0xFFFFFF)
    public static let darkTextSecondary = color(0xB3B3B3)
    public static let darkTextTertiary = color(0x808080)
    public static let darkDivider = Color.white.opacity(0.06)
    public static let darkDividerStrong = Color.white.opacity(0.10)

    public static let lightBackground = color(0xF2F1EE)
    public static let lightSurface = color(0xFCFBF9)
    /// Light mode already has enough contrast, so forms retain the card fill.
    public static let lightFormSurface = lightSurface
    public static let lightSurfaceElevated = color(0xEBEAE7)
    public static let lightSurfaceMuted = color(0xEEEDE9)
    public static let lightDanger = color(0xFF3B30)
    public static let lightWarning = color(0xFF9E18)
    public static let lightTextPrimary = color(0x111118)
    public static let lightTextSecondary = color(0x64646F)
    public static let lightTextTertiary = color(0x8E8E9A)
    public static let lightDivider = Color.black.opacity(0.06)
    public static let lightDividerStrong = Color.black.opacity(0.10)

    // MARK: - macOS app theme

    public static let macDarkBackground = color(0x1C1C1E)
    public static let macDarkSurface = color(0x2C2C2E)
    public static let macDarkFormSurface = color(0x343438)
    public static let macDarkSurfaceElevated = color(0x3A3A3C)
    public static let macDarkSurfaceMuted = color(0x242426)
    public static let macDarkDivider = Color.white.opacity(0.08)
    public static let macDarkDividerStrong = Color.white.opacity(0.12)
    public static let macToggleKnob = Color.white
    public static let macToggleKnobShadow = Color.black.opacity(0.25)
    public static let macToggleOffTrackDark = Color.white.opacity(0.18)
    public static let macToggleOffTrackLight = Color.black.opacity(0.15)
    public static let macOverlayShadow = Color.black.opacity(0.22)

    // MARK: - Recording and generated media

    public static let recordRed = color(0xFF3B30)
    public static let recordBlue = color(0x007AFF)
    public static let recordingWaveform = color(0xFFC7C7)
    public static let recordDiscHairlineIdle = Color.white.opacity(0.08)
    public static let recordDiscHairlineActive = Color.white.opacity(0.12)
    public static let recordDiscOverlayStroke = Color.white.opacity(0.16)
    public static let recordListeningRing = Color.white.opacity(0.28)
    public static let pictureInPictureOutline = color(0xE5E7EB)
    public static let pictureInPictureAccent = color(0x33C78C)

    // MARK: - Keyboard surfaces

    public static let keyboardDarkKeyFill = color(0x525252)
    public static let keyboardDarkKeyPressed = color(0x3B3B3B)
    public static let keyboardDarkInputFill = color(0x4D4D4D)
    public static let keyboardDarkInputFillRaised = color(0x5C5C5C)
    public static let keyboardDarkControlFill = color(0x383838)
    public static let keyboardDarkControlBorder = color(0x1F1F1F)
    public static let keyboardLightKeyPressed = color(0xD6D6D6)
    public static let keyboardLightControlBorder = Color.black.opacity(0.12)
    public static let keyboardActionBorderDark = Color.black.opacity(0.10)
    public static let keyboardActionBorderLight = Color.black.opacity(0.08)
    public static let keyboardLightText = color(0x0F0F14)
    public static let keyboardDarkSend = color(0x49B96A)
    public static let keyboardLightSend = color(0x328C4C)
    public static let keyboardDarkSendPressed = brandAccent
    public static let keyboardLightSendPressed = color(0x28723F)

    // MARK: - Fixed dark presentation surfaces

    public static let demoBackground = color(0x0F0F12)
    public static let demoSelectionInactive = Color.gray
    public static let accountAvatarOutline = Color.white.opacity(0.20)
    public static let accountAvatarGradients: [[Color]] = [
        [.indigo, .blue],
        [.purple, .pink],
        [.teal, .cyan],
        [.orange, .red],
        [.mint, .green]
    ]

    // MARK: - Shared effects

    public static let cardShadowNear = Color.black.opacity(0.018)
    public static let cardShadowMid = Color.black.opacity(0.018)
    public static let cardShadowFar = Color.black.opacity(0.025)
    public static let selectedCardFillLeadingDark = brandAccent.opacity(0.24)
    public static let selectedCardFillTrailingDark = brandAccent.opacity(0.15)
    public static let selectedCardFillLeadingLight = brandAccent.opacity(0.18)
    public static let selectedCardFillTrailingLight = brandAccent.opacity(0.11)
    public static let selectedCardStrokeDark = brandAccent.opacity(0.26)
    public static let selectedCardStrokeLight = brandAccent.opacity(0.18)
    public static let selectedCardShadowNearDark = brandAccent.opacity(0.12)
    public static let selectedCardShadowMidDark = brandAccent.opacity(0.075)
    public static let selectedCardShadowFarDark = brandAccent.opacity(0.035)
    public static let selectedCardShadowNearLight = brandAccent.opacity(0.075)
    public static let selectedCardShadowMidLight = brandAccent.opacity(0.05)
    public static let selectedCardShadowFarLight = brandAccent.opacity(0.03)

    // MARK: - Animated mesh palettes

    public static let meshAurora: [Color] = [
        color(0x0F1221),  // top-left
        color(0x1A1433),  // top-mid
        color(0x0D1A2E),  // top-right
        color(0x1F1729),  // left-mid
        color(0x2E1C38),  // center — deepest violet
        color(0x141F33),  // right-mid
        color(0x291A1A),  // bottom-left — amber hint
        color(0x1A142E),  // bottom-mid
        color(0x0D1724)   // bottom-right
    ]

    public static let meshPolar: [Color] = [
        color(0x0D121A),
        color(0x171F2E),
        color(0x121724),
        color(0x1A212E),
        color(0x212938),
        color(0x141A29),
        color(0x0F1A29),
        color(0x171C2E),
        color(0x0D121F)
    ]

    public static let meshEmber: [Color] = [
        color(0x140F0D),
        color(0x24170F),
        color(0x1A120F),
        color(0x291A12),
        color(0x382114),
        color(0x1F1412),
        color(0x1A0F0D),
        color(0x26170F),
        color(0x140F0D)
    ]

    private static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
