// Theme.swift
// OSGKeyboard · Design System
//
// Single source of truth for colour, spacing, corner radius, typography.
// Inspired by Dieter Rams ("less but better") and Apple Human Interface:
// every surface has a single purpose, every token earns its place, and
// the visual hierarchy is carried by *whitespace + one accent*, never by
// extra colour.

import SwiftUI

// MARK: - Theme palette (light / dark)

/// Single source of truth for *one* colour scheme. The active palette is
/// injected via the `\.themePalette` environment key — see
/// `DesignSystem/ThemedRoot.swift`. Token names mirror the previous
/// `Palette` static API so existing call sites (`Palette.background` etc.)
/// still compile and resolve through the legacy static accessors below.
public struct ThemePalette: Sendable, Equatable {
    public let background:      Color
    public let surface:         Color
    public let surfaceElevated: Color
    public let surfaceMuted:    Color

    public let accent:      Color
    public let accentMuted: Color
    public let accentGlow:  Color

    public let danger:  Color
    public let success: Color
    public let warning: Color

    public let textPrimary:   Color
    public let textSecondary: Color
    public let textTertiary:  Color
    public let textOnAccent:  Color

    public let divider:       Color
    public let dividerStrong: Color

    public let recordRed: Color
}

public enum Palette {
    // Backgrounds
    public static let background      = Color(red: 0.039, green: 0.039, blue: 0.043)  // #0A0A0B
    public static let surface         = Color(red: 0.094, green: 0.094, blue: 0.106)  // #18181B
    public static let surfaceElevated = Color(red: 0.153, green: 0.153, blue: 0.169)  // #27272A
    public static let surfaceMuted    = Color(red: 0.071, green: 0.071, blue: 0.082)  // #121215

    // Accents
    public static let accent          = Color(red: 0.227, green: 0.627, blue: 0.353)  // #3AA05A
    public static let accentMuted     = accent.opacity(0.18)
    public static let accentGlow      = accent.opacity(0.42)

    // Semantic
    public static let danger          = Color(red: 1.000, green: 0.271, blue: 0.227)  // #FF453A
    public static let success         = accent  // unified brand green in UI
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

    /// Canonical dark palette — preserves every legacy literal above so
    /// existing call sites that read `Palette.background` directly keep
    /// getting the dark value (important for the keyboard extension, which
    /// deliberately stays dark regardless of system appearance).
    public static let dark = ThemePalette(
        background:      background,
        surface:         surface,
        surfaceElevated: surfaceElevated,
        surfaceMuted:    surfaceMuted,
        accent:          accent,
        accentMuted:     accentMuted,
        accentGlow:      accentGlow,
        danger:          danger,
        success:         success,
        warning:         warning,
        textPrimary:     textPrimary,
        textSecondary:   textSecondary,
        textTertiary:    textTertiary,
        textOnAccent:    textOnAccent,
        divider:         divider,
        dividerStrong:   dividerStrong,
        recordRed:       recordRed
    )

    /// Light palette — warm gray backgrounds for daytime use.
    public static let light = ThemePalette(
        background:      Color(red: 0.949, green: 0.945, blue: 0.933),  // #F2F1EE warm gray
        surface:         Color(red: 0.988, green: 0.984, blue: 0.976),  // #FCFBF9
        surfaceElevated: Color(red: 0.922, green: 0.918, blue: 0.906),  // #EBEAE7
        surfaceMuted:    Color(red: 0.933, green: 0.929, blue: 0.918),  // #EEEDE9
        accent:          Color(red: 0.227, green: 0.627, blue: 0.353),  // #3AA05A
        accentMuted:     Color(red: 0.227, green: 0.627, blue: 0.353).opacity(0.14),
        accentGlow:      Color(red: 0.227, green: 0.627, blue: 0.353).opacity(0.32),
        danger:          Color(red: 1.000, green: 0.231, blue: 0.188),  // #FF3B30
        success:         Color(red: 0.227, green: 0.627, blue: 0.353),  // same as accent
        warning:         Color(red: 1.000, green: 0.620, blue: 0.094),  // #FF9E18
        textPrimary:     Color(red: 0.067, green: 0.067, blue: 0.094),  // #111118
        textSecondary:   Color(red: 0.392, green: 0.392, blue: 0.435),  // #64646F
        textTertiary:    Color(red: 0.557, green: 0.557, blue: 0.604),  // #8E8E9A
        textOnAccent:    Color.white,
        divider:         Color.black.opacity(0.06),
        dividerStrong:   Color.black.opacity(0.10),
        recordRed:       Color(red: 1.000, green: 0.231, blue: 0.188)   // #FF3B30
    )
}

// MARK: - Environment key

private struct ThemePaletteKey: EnvironmentKey {
    /// Default falls back to the legacy dark palette so views that haven't
    /// been wrapped in `ThemedRoot` continue to look identical to today.
    static let defaultValue: ThemePalette = Palette.dark
}

public extension EnvironmentValues {
    /// The palette currently active for this view. Reads from the nearest
    /// `ThemedRoot` ancestor (or `Palette.dark` if none).
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
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

public enum SettingsListMetrics {
    /// Floor for settings list rows (slightly above HIG 44pt).
    /// Row height grows with content; this only enforces a touch-target minimum.
    public static let singleLineMinHeight: CGFloat = 48
    /// Horizontal inset inside a settings list row.
    public static let rowHorizontalPadding: CGFloat = Spacing.md
    /// Vertical inset inside a settings list row (`Spacing.sm`).
    public static let rowVerticalPadding: CGFloat = 12
    /// Space between a section label and its card.
    public static let sectionLabelSpacing: CGFloat = Spacing.sm
}

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
    /// Home brand line + History / Dictionary / Settings page titles.
    public static let pageTitle  = Font.system(size: 30, weight: .semibold)
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    /// Subtle status line under the brand mark (home header).
    public static let status     = Font.system(size: 13, weight: .regular)
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
//
// Each modifier is a proper ViewModifier struct so it can read the
// active ThemePalette from @Environment. This is the ONLY way to make
// shared modifiers respect light/dark mode — plain View extension
// methods cannot access environment values.

private struct CardSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var palette
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
    }
}

private struct PillChipModifier: ViewModifier {
    @Environment(\.themePalette) private var palette
    let foreground: Color?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(palette.surfaceElevated, in: Capsule())
            .foregroundStyle(foreground ?? palette.textSecondary)
    }
}

private struct PrimaryButtonModifier: ViewModifier {
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(TypeStyle.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(palette.accent, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .foregroundStyle(palette.textOnAccent)
    }
}

private struct SecondaryButtonModifier: ViewModifier {
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        content
            .font(TypeStyle.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.dividerStrong, lineWidth: 0.5)
            )
            .foregroundStyle(palette.textPrimary)
    }
}

public extension View {
    /// Standard settings list row insets: horizontal + vertical padding and a
    /// touch-target floor. Height grows with content — do not hand-roll
    /// per-section padding/`minHeight` for ordinary settings rows.
    func settingsListRow(
        minHeight: CGFloat = SettingsListMetrics.singleLineMinHeight,
        alignment: Alignment = .center
    ) -> some View {
        self
            .padding(.horizontal, SettingsListMetrics.rowHorizontalPadding)
            .padding(.vertical, SettingsListMetrics.rowVerticalPadding)
            .frame(minHeight: minHeight, alignment: alignment)
    }

    /// Standard card surface used in the main app.
    func cardSurface(padding: CGFloat = Spacing.md) -> some View {
        modifier(CardSurfaceModifier(padding: padding))
    }

    /// Muted pill (used for tags, locale indicators, etc.).
    /// Pass nil to inherit palette.textSecondary automatically.
    func pillChip(foreground: Color? = nil) -> some View {
        modifier(PillChipModifier(foreground: foreground))
    }

    /// Primary CTA button.
    func primaryButton() -> some View {
        modifier(PrimaryButtonModifier())
    }

    /// Secondary CTA button.
    func secondaryButton() -> some View {
        modifier(SecondaryButtonModifier())
    }
}
