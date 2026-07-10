// MacComponents.swift
// OSGKeyboard · Mac
//
// Reusable macOS UI pieces styled with the shared design tokens and the
// system-native palette (see MacTheme.swift). Kept as plain SwiftUI (no
// AppKit) so they can be reused on iPadOS. Settings / History / Dictionary
// now use the native grouped `Form`, so the old hand-rolled card/row types
// were removed — what remains here is used by the Dashboard, the status
// footer and the menu-bar popover.

import SwiftUI

// MARK: - Shared layout metrics

/// Fixed metrics that keep every desktop surface on the same grid.
enum MacMetrics {
    /// Uniform max width for trailing text controls (API key / model field).
    static let controlWidth: CGFloat = 240
    /// Sidebar width and the horizontal inset shared by brand, nav and footer.
    static let sidebarWidth: CGFloat = 240
    /// Horizontal inset for sidebar chrome (nav rows, footer). The brand logo
    /// adds `Spacing.sm` on top of this so its left edge lines up with the
    /// SF Symbol in each nav `Label`.
    static let sidebarInset: CGFloat = Spacing.md
    static let sidebarContentInset: CGFloat = sidebarInset + Spacing.sm
    /// Reading width for single-column content.
    static let contentMaxWidth: CGFloat = 720
    /// Horizontal inset for page titles and scroll *content* (cards).
    /// ScrollViews / Forms stay full-bleed so the scrollbar sits on the
    /// window edge; only the content inside is inset.
    /// Doubled from `Spacing.lg` so title + cards breathe from the edges.
    static let pageHorizontalInset: CGFloat = Spacing.lg * 2
    /// Built-in horizontal inset macOS grouped `Form` adds around its section
    /// cards, on top of any padding we apply. Subtracted from
    /// `pageHorizontalInset` on the Settings Form so its card outer edge lands
    /// on `pageHorizontalInset` — matching the History page and the page title.
    static let groupedFormSectionInset: CGFloat = Spacing.lg
    /// Default (= minimum) main-window size. Opening the app uses this size;
    /// the window cannot shrink below it.
    static let windowMinWidth: CGFloat = 860
    static let windowMinHeight: CGFloat = 600
    /// Compact dictation-canvas height so Home fits the min window without scrolling.
    static let dictationCanvasMinHeight: CGFloat = 120
    /// Top inset that clears the window traffic-light buttons now that the
    /// title bar is hidden.
    static let trafficLightInset: CGFloat = 28
}

// MARK: - Liquid Glass

private struct MacGlassSurface<S: Shape>: ViewModifier {
    @Environment(\.themePalette) private var palette
    let shape: S
    let fillOpacity: Double

    func body(content: Content) -> some View {
        // Flat, shadowless surface fill. We deliberately avoid `glassEffect`
        // here: on macOS 26 Liquid Glass adds a raised drop shadow to every
        // card, which reads as visual noise for content containers. Hierarchy
        // is carried by the surface colour + hairline border instead.
        content
            .background(palette.surface.opacity(fillOpacity), in: shape)
    }
}

extension View {
    /// Applies a flat semantic surface fill (no drop shadow) behind `content`.
    func macGlassSurface<S: Shape>(
        in shape: S,
        fillOpacity: Double = 0.72
    ) -> some View {
        modifier(MacGlassSurface(shape: shape, fillOpacity: fillOpacity))
    }
}

// MARK: - Text field styling

/// Text-field chrome aligned with native macOS Form controls: compact
/// height, text-background fill, hairline border.
private struct MacFieldStyleModifier: ViewModifier {
    @Environment(\.themePalette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(TypeStyle.footnote)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Color(nsColor: .textBackgroundColor), in: shape)
            .overlay(shape.stroke(palette.divider, lineWidth: 0.5))
    }
}

extension View {
    /// Theme-aware text-field styling for the settings inputs.
    func macFieldStyle() -> some View { modifier(MacFieldStyleModifier()) }
}

// MARK: - Page header

/// Page title for History / Dictionary / Settings. Applies the shared
/// `pageHorizontalInset` so its left edge matches inset card content below.
/// Type size matches Home's brand line (`TypeStyle.pageTitle`).
struct MacPageHeader<Trailing: View>: View {
    @Environment(\.themePalette) private var palette
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(TypeStyle.pageTitle)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, MacMetrics.pageHorizontalInset)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.sm)
    }
}

extension MacPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Card container

/// Elevated surface used for stat tiles and the dictation canvas.
struct MacCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    var padding: CGFloat = Spacing.md
    var cornerRadius: CGFloat = Radius.medium
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content()
            .padding(padding)
            .macGlassSurface(in: shape, fillOpacity: 1)
            .overlay(
                shape
                    .stroke(palette.divider, lineWidth: 0.5)
            )
    }
}

// MARK: - Stat tile

struct StatCard: View {
    @Environment(\.themePalette) private var palette
    let title: String
    let value: String
    let caption: String
    var systemImage: String?
    var accent: Bool = false
    /// Hero metric: wide horizontal layout that uses full-card width without
    /// stretching to fill dead vertical space — used for the primary word count.
    var prominent: Bool = false

    var body: some View {
        MacCard(padding: prominent ? Spacing.md : Spacing.md) {
            if prominent {
                prominentBody
            } else {
                compactBody
            }
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(title.uppercased())
                    .font(TypeStyle.caption2)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent ? palette.accent : palette.textTertiary)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            Text(value)
                .font(TypeStyle.title2)
                .foregroundStyle(accent ? palette.accent : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(Motion.soft, value: value)
            Text(caption)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wide "hero bar" layout: icon badge + title/caption on the left, the
    /// big number anchored right — fills the full card width edge-to-edge
    /// instead of a tall card with empty space below a small number.
    private var prominentBody: some View {
        HStack(spacing: Spacing.md) {
            if let systemImage {
                ZStack {
                    Circle()
                        .fill(palette.accentMuted)
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(TypeStyle.caption2)
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(caption)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: Spacing.md)
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(accent ? palette.accent : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(Motion.soft, value: value)
        }
    }
}

// MARK: - Live waveform

/// Compact bar visualiser reacting to the input level while recording.
struct MiniWaveform: View {
    @Environment(\.themePalette) private var palette
    let level: Float
    var barCount: Int = 5
    /// Pass nil to inherit the palette accent automatically.
    var tint: Color?
    /// Peak bar height; overlay HUD uses a taller meter than the mic button.
    var maxBarHeight: CGFloat = 22
    var barWidth: CGFloat = 3
    var barSpacing: CGFloat = 3

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(tint ?? palette.accent)
                    .frame(width: barWidth, height: barHeight(index))
            }
        }
        .frame(height: maxBarHeight)
        .animation(Motion.instant, value: level)
        .onAppear {
            withAnimation(.linear(duration: 0.75).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        // Stronger level coupling + staggered phase so the meter reads as
        // "alive" even at modest mic levels.
        let boosted = min(1, CGFloat(level) * 1.35 + 0.08)
        let base = boosted * maxBarHeight
        let wobble = sin((phase * .pi * 2) + CGFloat(index) * 0.85) * (maxBarHeight * 0.22)
            + (maxBarHeight * 0.12)
        let parity = 0.55 + CGFloat(index % 3) * 0.2
        return max(maxBarHeight * 0.18, min(maxBarHeight, base * parity + wobble))
    }
}

// MARK: - Translation display helper

/// Shared label logic for the translation control so the dashboard chip,
/// the status footer and the menu-bar popover all read identically.
enum MacTranslationDisplay {
    static func label(for targetLocaleId: String, language: AppUILanguage) -> String {
        let resolved = TranslationLanguageCatalog.resolve(targetLocaleId)
        if TranslationLanguageCatalog.isOff(resolved.id) {
            return MacL10n.string("keyboard.translation.offMenu", language: language)
        }
        return resolved.nativeName
    }
}

// MARK: - Status footer

/// Bottom status strip: engine mode, translation target, connection —
/// kept visually quiet so it never competes with the record bar.
struct MacStatusFooter: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()
            Label(
                viewModel.isCloudMode
                    ? MacL10n.string("mac.mode.cloud", language: lang)
                    : MacL10n.string("mac.mode.local", language: lang),
                systemImage: viewModel.isCloudMode ? "cloud" : "cpu"
            )
            .contentTransition(.opacity)

            Text("·")
                .foregroundStyle(palette.textTertiary.opacity(0.5))

            Label(
                MacTranslationDisplay.label(for: viewModel.config.translationTargetLocaleId, language: lang),
                systemImage: "translate"
            )
            .contentTransition(.opacity)

            Text("·")
                .foregroundStyle(palette.textTertiary.opacity(0.5))

            Label(MacL10n.string("mac.connected", language: lang), systemImage: "link")
                .foregroundStyle(palette.accent.opacity(0.85))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textTertiary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, MacMetrics.pageHorizontalInset)
        .padding(.vertical, Spacing.sm)
        .animation(Motion.quick, value: viewModel.isCloudMode)
        .animation(Motion.quick, value: viewModel.config.translationTargetLocaleId)
    }
}

// MARK: - Form alignment

private struct MacFormPageAlignModifier: ViewModifier {
    func body(content: Content) -> some View {
        // Form stays full-bleed (scrollbar on the window edge). Section
        // cards are inset to match `MacPageHeader`.
        content
            .contentMargins(.horizontal, MacMetrics.pageHorizontalInset, for: .scrollContent)
    }
}

extension View {
    /// Insets grouped-`Form` section cards to `pageHorizontalInset`.
    func macFormPageAligned() -> some View {
        modifier(MacFormPageAlignModifier())
    }
}
