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

// MARK: - Card container

/// Elevated surface used for stat tiles and the dictation canvas.
struct MacCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    var padding: CGFloat = Spacing.md
    @ViewBuilder var content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)

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

    var body: some View {
        MacCard {
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

    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(tint ?? palette.accent)
                    .frame(width: 3, height: barHeight(index))
            }
        }
        .frame(height: 22)
        .animation(Motion.instant, value: level)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let base = CGFloat(level) * 22
        let wobble = sin((phase * .pi * 2) + CGFloat(index)) * 4 + 4
        return max(4, min(22, base * (0.6 + CGFloat(index % 2) * 0.4) + wobble))
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

/// Bottom status strip: engine mode (cloud/local), translation target, and
/// the connection state — icons and wording mirror the dashboard record bar.
struct MacStatusFooter: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    var body: some View {
        HStack(spacing: Spacing.md) {
            Spacer()
            Label(
                viewModel.isCloudMode
                    ? MacL10n.string("mac.mode.cloud", language: lang)
                    : MacL10n.string("mac.mode.local", language: lang),
                systemImage: viewModel.isCloudMode ? "cloud" : "cpu"
            )
            .foregroundStyle(palette.textSecondary)
            .contentTransition(.opacity)

            Label(
                MacTranslationDisplay.label(for: viewModel.config.translationTargetLocaleId, language: lang),
                systemImage: "translate"
            )
            .foregroundStyle(palette.textSecondary)
            .contentTransition(.opacity)

            Label(MacL10n.string("mac.connected", language: lang), systemImage: "link")
                .foregroundStyle(palette.accent)
        }
        .font(TypeStyle.caption)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
        .animation(Motion.quick, value: viewModel.isCloudMode)
        .animation(Motion.quick, value: viewModel.config.translationTargetLocaleId)
    }
}
