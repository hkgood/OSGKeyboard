// Theme.swift
// OSGKeyboard · Design System
//
// Semantic theme roles, spacing, corner radius, and typography. Canonical
// custom colour values live in `ColorLibrary.swift`.
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
    public let background: Color
    public let surface: Color
    public let formSurface: Color
    public let surfaceElevated: Color
    public let surfaceMuted: Color

    public let accent: Color
    public let accentMuted: Color
    public let accentGlow: Color
    /// Distinguishes AI listening / generation from ordinary dictation.
    public let aiTeal: Color

    public let danger: Color
    public let success: Color
    public let warning: Color

    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let textOnAccent: Color

    public let divider: Color
    public let dividerStrong: Color

    public let recordRed: Color
    /// Alternate recording accent available to platform-specific surfaces.
    public let recordBlue: Color
}

public enum Palette {
    // Backgrounds
    public static let background      = OSGColor.darkBackground
    public static let surface         = OSGColor.darkSurface
    public static let formSurface     = OSGColor.darkFormSurface
    public static let surfaceElevated = OSGColor.darkSurfaceElevated
    public static let surfaceMuted    = OSGColor.darkSurfaceMuted

    // Accents
    public static let accent          = OSGColor.brandAccent
    public static let accentMuted     = accent.opacity(0.18)
    public static let accentGlow      = accent.opacity(0.42)
    public static let aiTeal           = OSGColor.aiTeal

    // Semantic
    public static let danger          = OSGColor.darkDanger
    public static let success         = accent  // unified brand green in UI
    public static let warning         = OSGColor.darkWarning

    // Text
    public static let textPrimary     = OSGColor.darkTextPrimary
    public static let textSecondary   = OSGColor.darkTextSecondary
    public static let textTertiary    = OSGColor.darkTextTertiary
    public static let textOnAccent    = OSGColor.fixedDarkContent

    // Lines
    public static let divider         = OSGColor.darkDivider
    public static let dividerStrong   = OSGColor.darkDividerStrong

    // Recording state
    public static let recordRed       = OSGColor.recordRed
    public static let recordBlue      = OSGColor.recordBlue

    /// Canonical dark palette — preserves every legacy literal above so
    /// existing call sites that read `Palette.background` directly keep
    /// getting the dark value (important for the keyboard extension, which
    /// deliberately stays dark regardless of system appearance).
    public static let dark = ThemePalette(
        background: background,
        surface: surface,
        formSurface: formSurface,
        surfaceElevated: surfaceElevated,
        surfaceMuted: surfaceMuted,
        accent: accent,
        accentMuted: accentMuted,
        accentGlow: accentGlow,
        aiTeal: aiTeal,
        danger: danger,
        success: success,
        warning: warning,
        textPrimary: textPrimary,
        textSecondary: textSecondary,
        textTertiary: textTertiary,
        textOnAccent: textOnAccent,
        divider: divider,
        dividerStrong: dividerStrong,
        recordRed: recordRed,
        recordBlue: recordBlue
    )

    /// Light palette — warm gray backgrounds for daytime use.
    public static let light = ThemePalette(
        background: OSGColor.lightBackground,
        surface: OSGColor.lightSurface,
        formSurface: OSGColor.lightFormSurface,
        surfaceElevated: OSGColor.lightSurfaceElevated,
        surfaceMuted: OSGColor.lightSurfaceMuted,
        accent: OSGColor.brandAccent,
        accentMuted: OSGColor.brandAccent.opacity(0.14),
        accentGlow: OSGColor.brandAccent.opacity(0.32),
        aiTeal: OSGColor.aiTeal,
        danger: OSGColor.lightDanger,
        success: OSGColor.brandAccent,
        warning: OSGColor.lightWarning,
        textPrimary: OSGColor.lightTextPrimary,
        textSecondary: OSGColor.lightTextSecondary,
        textTertiary: OSGColor.lightTextTertiary,
        textOnAccent: OSGColor.fixedLightContent,
        divider: OSGColor.lightDivider,
        dividerStrong: OSGColor.lightDividerStrong,
        recordRed: OSGColor.recordRed,
        recordBlue: OSGColor.recordBlue
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
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 40
    public static let hero: CGFloat = 48
}

/// Semantic spacing for sibling card surfaces.
public enum CardLayoutMetrics {
    /// Vertical gap between page-level cards or card sections.
    public static let sectionSpacing: CGFloat = 18
    /// Horizontal and vertical gap between compact cards or list-item cards.
    public static let compactItemSpacing: CGFloat = Spacing.xs
}

// MARK: - Corner radius scale

public enum Radius {
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 24
    public static let pill: CGFloat = 999
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
            .cardElevation()
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
