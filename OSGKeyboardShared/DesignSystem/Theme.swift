// Theme.swift
// OSGKeyboard · Design System
//
// Single source of truth for colour, spacing, corner radius, typography.
// Inspired by Dieter Rams ("less but better") and Apple Human Interface:
// every surface has a single purpose, every token earns its place, and
// the visual hierarchy is carried by *whitespace + one accent*, never by
// extra colour.

import SwiftUI

// MARK: - Palette

public enum Palette {
    // Backgrounds
    public static let background      = Color(red: 0.039, green: 0.039, blue: 0.043)  // #0A0A0B
    public static let surface         = Color(red: 0.094, green: 0.094, blue: 0.106)  // #18181B
    public static let surfaceElevated = Color(red: 0.153, green: 0.153, blue: 0.169)  // #27272A
    public static let surfaceMuted    = Color(red: 0.071, green: 0.071, blue: 0.082)  // #121215

    // Accents
    public static let accent          = Color(red: 0.353, green: 0.784, blue: 0.980)  // #5AC8FA
    public static let accentMuted     = accent.opacity(0.18)
    public static let accentGlow      = accent.opacity(0.42)

    // Semantic
    public static let danger          = Color(red: 1.000, green: 0.271, blue: 0.227)  // #FF453A
    public static let success         = Color(red: 0.157, green: 0.812, blue: 0.412)  // #28CF69
    public static let warning         = Color(red: 1.000, green: 0.749, blue: 0.094)  // #FFBF18

    // Text
    public static let textPrimary     = Color.white
    public static let textSecondary   = Color(white: 0.7)
    public static let textTertiary    = Color(white: 0.50)
    public static let textOnAccent    = Color.black

    // Lines
    public static let divider         = Color.white.opacity(0.06)
    public static let dividerStrong   = Color.white.opacity(0.10)

    // Recording state
    public static let recordRed       = Color(red: 1.000, green: 0.231, blue: 0.188)  // #FF3B30
}

// MARK: - Spacing scale (4 pt grid)

public enum Spacing {
    public static let xxs:  CGFloat = 4
    public static let xs:   CGFloat = 8
    public static let sm:   CGFloat = 12
    public static let md:   CGFloat = 16
    public static let lg:   CGFloat = 20
    public static let xl:   CGFloat = 24
    public static let xxl:  CGFloat = 32
    public static let xxxl: CGFloat = 40
    public static let hero: CGFloat = 48
}

// MARK: - Corner radius scale

public enum Radius {
    public static let small:  CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large:  CGFloat = 16
    public static let xl:     CGFloat = 20
    public static let xxl:    CGFloat = 24
    public static let pill:   CGFloat = 999
}

// MARK: - Typography

public enum TypeStyle {
    public static let caption2   = Font.system(size: 11, weight: .medium)
    public static let caption    = Font.system(size: 12, weight: .medium)
    public static let footnote   = Font.system(size: 13, weight: .regular)
    public static let body       = Font.system(size: 15, weight: .regular)
    public static let bodyEmph   = Font.system(size: 15, weight: .medium)
    public static let headline   = Font.system(size: 17, weight: .semibold)
    public static let title3     = Font.system(size: 20, weight: .semibold)
    public static let title2     = Font.system(size: 22, weight: .bold)
    public static let title      = Font.system(size: 28, weight: .bold)
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    public static let mono       = Font.system(size: 13, weight: .regular, design: .monospaced)
    public static let monoSmall  = Font.system(size: 11, weight: .regular, design: .monospaced)
}

// MARK: - Animation

public enum Motion {
    public static let quick     = Animation.spring(response: 0.25, dampingFraction: 0.85)
    public static let soft      = Animation.spring(response: 0.40, dampingFraction: 0.80)
    public static let deliberate = Animation.spring(response: 0.55, dampingFraction: 0.78)
    public static let breath    = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    public static let instant   = Animation.linear(duration: 0.12)
}

// MARK: - Reusable view modifiers

public extension View {
    /// Standard card surface used in the main app.
    func cardSurface(padding: CGFloat = Spacing.md) -> some View {
        self
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(Palette.divider, lineWidth: 0.5)
            )
    }

    /// Muted pill (used for tags, locale indicators, etc.).
    func pillChip(foreground: Color = Palette.textSecondary) -> some View {
        self
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(Palette.surfaceElevated, in: Capsule())
            .foregroundStyle(foreground)
    }

    /// Primary CTA button.
    func primaryButton() -> some View {
        self
            .font(TypeStyle.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .foregroundStyle(Palette.textOnAccent)
    }

    /// Secondary CTA button.
    func secondaryButton() -> some View {
        self
            .font(TypeStyle.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(Palette.dividerStrong, lineWidth: 0.5)
            )
            .foregroundStyle(Palette.textPrimary)
    }

    /// Legacy alias for older call sites.
    func cardStyle() -> some View { cardSurface() }
}

// MARK: - Backwards compat (legacy callers in old code)

public enum Theme {
    public static let background     = Palette.background
    public static let card           = Palette.surface
    public static let accent         = Palette.accent
    public static let danger         = Palette.danger
    public static let textPrimary    = Palette.textPrimary
    public static let textSecondary  = Palette.textSecondary
    public static let divider        = Palette.divider
}
