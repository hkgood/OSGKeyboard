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
    /// Shared height for credential inputs and icon buttons — matches the iOS
    /// settings controls (38).
    static let settingsControlHeight: CGFloat = 38
    /// Fixed label column for provider rows: wider than iOS (150) so the label
    /// text takes a larger share of the row and the trailing control narrows.
    static let settingLabelWidth: CGFloat = 200
    /// Uniform minimum height for every settings row, so rows read as an even
    /// list regardless of whether they hold a 38pt control or a single-line
    /// label. Content is centered within it; taller rows (status text, progress)
    /// grow past it.
    static let settingsRowMinHeight: CGFloat = 40
    /// The single vertical rhythm for settings cards: the gap *between* rows AND
    /// the padding between a card's top/bottom edge and its first/last row are
    /// both this value, so the card breathes evenly. Applied as `VStack(spacing:)`
    /// between rows and `.padding(.vertical:)` on the card body.
    static let settingsRowGap: CGFloat = Spacing.md
    /// Provider menu trigger width (legacy).
    static let selectWidth: CGFloat = 200
    /// Text-field max width for provider credential rows (narrower than the
    /// old 360pt so long keys truncate instead of wrapping when the window shrinks).
    static let fieldWidth: CGFloat = 280
    /// Legacy alias used by older call sites; prefer `fieldWidth`.
    static let controlWidth: CGFloat = fieldWidth
    /// Horizontal inset inside settings cards — matches History / Dictionary rows.
    static let settingsCardInset: CGFloat = Spacing.md
    /// Below this row width, provider rows stack label above control.
    static let settingsCompactBreakpoint: CGFloat = 520
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

// MARK: - Settings typography (mirrors the iOS settings rows)

/// Type scale that maps 1:1 to the iOS settings controls so the desktop and
/// phone read identically: row label / picker value at body (15), hints at
/// caption2 (11), section header at caption2 (uppercased at the call site).
enum MacSettingsType {
    static let sectionTitle = TypeStyle.caption2
    static let rowLabel     = TypeStyle.body
    static let control      = TypeStyle.body
    static let controlEmph  = TypeStyle.bodyEmph
    static let hint         = TypeStyle.caption2
    static let button       = TypeStyle.body
}

// MARK: - iOS-style toggle

/// Pill switch mirroring the iOS settings toggle: accent track when on, neutral
/// when off, 16pt white knob, spring slide. Colours resolve through the active
/// OSG palette so it follows the app theme.
struct MacToggleStyle: ToggleStyle {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? palette.accent : offTrackColor)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 36, height: 20)
            .animation(Motion.quick, value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }

    private var offTrackColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.18)
            : Color.black.opacity(0.15)
    }
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

/// Theme-aware credential field chrome — comfortable tap target,
/// monospaced-friendly body size, and a fill/border that stays clearly
/// distinct from the section card in both appearances.
private struct MacFieldStyleModifier: ViewModifier {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    var monospaced: Bool = false

    func body(content: Content) -> some View {
        // Mirrors the iOS credential field: recessed surface-elevated fill,
        // medium radius, hairline border, comfortable 38pt tap target.
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        content
            .textFieldStyle(.plain)
            .font(monospaced ? TypeStyle.mono : TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: MacMetrics.settingsControlHeight)
            .background(fieldFill, in: shape)
            .overlay(shape.stroke(palette.divider, lineWidth: 0.5))
    }

    /// Light mode: the section card reads near-white, so a recessed `surfaceElevated`
    /// grey barely differs. Use the system text-input background (true white) so the
    /// field reads as an editable well. Dark mode keeps the elevated grey, which sits
    /// *lighter* than the card and already stands out.
    private var fieldFill: Color {
        #if os(macOS)
        if colorScheme != .dark {
            return Color(nsColor: .textBackgroundColor)
        }
        #endif
        return palette.surfaceElevated
    }
}

extension View {
    /// Theme-aware text-field styling for the settings inputs.
    func macFieldStyle(monospaced: Bool = false) -> some View {
        modifier(MacFieldStyleModifier(monospaced: monospaced))
    }
}

// MARK: - Provider settings chrome

/// Section header + `MacCard` shell — same outer alignment as History /
/// Dictionary (title and card share `pageHorizontalInset` from the parent).
struct MacSettingsSection<Content: View>: View {
    @Environment(\.themePalette) private var palette

    let title: String
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(MacSettingsType.sectionTitle)
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            MacCard(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                // Card top/bottom breathe on the same rhythm as the gaps between
                // rows (rows own their own inter-row spacing via their container).
                .padding(.vertical, MacMetrics.settingsRowGap)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// iOS-style inline row: title (+ optional subtitle) on the left, control
/// right-aligned. Used by simple picker / toggle rows.
struct MacInlineRow<Control: View>: View {
    @Environment(\.themePalette) private var palette

    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(MacSettingsType.rowLabel)
                    .foregroundStyle(palette.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(MacSettingsType.hint)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Spacing.sm)
            control()
        }
        .padding(.horizontal, MacMetrics.settingsCardInset)
        .frame(minHeight: MacMetrics.settingsRowMinHeight)
    }
}

/// Backwards-compatible alias: title + optional subtitle + trailing control.
struct MacFormSubtitleRow<Control: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        MacInlineRow(title: title, subtitle: subtitle) {
            control()
        }
    }
}

/// Tappable navigation / action row inside a settings card.
struct MacFormLinkRow: View {
    @Environment(\.themePalette) private var palette

    let title: String
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, MacMetrics.settingsCardInset)
        .frame(minHeight: MacMetrics.settingsRowMinHeight)
        .contentShape(Rectangle())
    }
}

/// Single merged card body for LLM / ASR provider configuration sections.
struct MacSettingsProviderCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: MacMetrics.settingsRowGap) {
            content()
        }
    }
}

// MARK: - Responsive provider setting row

/// Label + control row for provider cards. Uses a two-column layout at
/// comfortable widths and stacks vertically when horizontal space is tight.
struct MacProviderSettingRow<Content: View>: View {
    @Environment(\.themePalette) private var palette

    let title: String
    var subtitle: String? = nil
    /// Retained for source compatibility; the control now fills its column.
    var controlMaxWidth: CGFloat? = nil
    /// Cross-axis alignment between the label column and the control. Provider
    /// rows keep `.top` (model row grows a status line below its field); single
    /// control rows can pass `.center` to vertically center label and control.
    var verticalAlignment: VerticalAlignment = .top
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: verticalAlignment, spacing: Spacing.md) {
            label
                .frame(width: MacMetrics.settingLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Uniform row height (content centered); inter-row spacing is owned by the
        // enclosing card, so the row adds no vertical padding of its own.
        .frame(maxWidth: .infinity, minHeight: MacMetrics.settingsRowMinHeight, alignment: .leading)
        .padding(.horizontal, MacMetrics.settingsCardInset)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
                .font(MacSettingsType.rowLabel)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(MacSettingsType.hint)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Align the title with the first 38pt control row, not with any
        // status/help text that appears below the control.
        .frame(minHeight: MacMetrics.settingsControlHeight, alignment: .leading)
    }
}

/// Square icon button matching credential field height.
struct MacSettingsIconButton: View {
    @Environment(\.themePalette) private var palette

    let systemName: String
    var help: String? = nil
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(disabled ? palette.textTertiary : palette.textSecondary)
                .frame(width: MacMetrics.settingsControlHeight, height: MacMetrics.settingsControlHeight)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(palette.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help ?? "")
    }
}

/// Compact tool button for validate / fetch-models actions.
struct MacSettingsToolButton: View {
    @Environment(\.themePalette) private var palette

    let title: String
    /// Background fill. Defaults to the neutral elevated surface.
    var fill: Color? = nil
    /// Text color. Defaults to primary text (tertiary when disabled).
    var foreground: Color? = nil
    /// Hairline divider border — drawn for the neutral variant, hidden for
    /// colored fills (delete / download) so the fill reads as the button.
    var showsBorder: Bool = true
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        Button(action: action) {
            Text(title)
                .font(MacSettingsType.button)
                .foregroundStyle(resolvedForeground)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 34)
                .background(fill ?? palette.surfaceElevated, in: shape)
                .overlay {
                    if showsBorder {
                        shape.stroke(palette.divider, lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var resolvedForeground: Color {
        if disabled { return palette.textTertiary }
        return foreground ?? palette.textPrimary
    }
}

// MARK: - Legacy setting row

/// Fixed label column + left-aligned control. Prefer `MacProviderSettingRow`
/// for provider configuration cards.
struct MacSettingRow<Content: View>: View {
    let title: String
    var controlMaxWidth: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        MacProviderSettingRow(title: title, controlMaxWidth: controlMaxWidth) {
            content()
        }
    }
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

            // Current models, shown just before the engine mode. Label text is
            // the model name only; the full "provider · model" lives in the
            // hover tooltip to keep the strip quiet.
            Label(asrModel.name, systemImage: "waveform")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .trailing)
                .help(asrModel.tooltip)
                .contentTransition(.opacity)

            Text("·")
                .foregroundStyle(palette.textTertiary.opacity(0.5))

            Label(llmModel.name, systemImage: "sparkles")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .trailing)
                .help(llmModel.tooltip)
                .contentTransition(.opacity)

            Text("·")
                .foregroundStyle(palette.textTertiary.opacity(0.5))

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
        .animation(Motion.quick, value: asrModel.name)
        .animation(Motion.quick, value: llmModel.name)
    }

    // MARK: - Current model resolution

    /// ASR: cloud shows the configured provider's model (or its default);
    /// local shows the selected on-device model's display name.
    private var asrModel: (name: String, tooltip: String) {
        let config = viewModel.config
        if viewModel.isCloudMode {
            let providerName = ProviderDisplayName.name(for: config.asrProviderId, language: lang)
            let model = config.asrModel.isEmpty
                ? CloudASRModelCatalog.defaultModel(for: config.asrProviderId)
                : config.asrModel
            return (model, "\(providerName) · \(model)")
        }
        let providerName = MacL10n.string("mac.mode.local", language: lang)
        let model = MacLocalASRModelName.displayName(for: MacLocalASRPreferences.selectedModelId, language: lang)
        return (model, "\(providerName) · \(model)")
    }

    /// LLM: cloud uses the configured provider; local routes through
    /// `localModeProviderId` (built-in DeepSeek unless the user supplied a key).
    private var llmModel: (name: String, tooltip: String) {
        let config = viewModel.config
        let providerId = viewModel.isCloudMode ? config.providerId : config.localModeProviderId
        let providerName = ProviderDisplayName.name(for: providerId, language: lang)
        let model: String
        if providerId == config.providerId, !config.model.isEmpty {
            model = config.model
        } else {
            model = LLMProvider.provider(id: providerId).defaultModel
        }
        return (model, "\(providerName) · \(model)")
    }
}

/// Cached lookup from a local ASR model id to its catalog display name. The
/// bundled catalog is small and immutable, so decoding it once is enough.
enum MacLocalASRModelName {
    private static let catalog: LocalASRCatalogDocument? = try? LocalASRModelCatalog.loadBundled()

    static func displayName(for modelId: String, language: AppUILanguage) -> String {
        if !modelId.isEmpty,
           let catalog,
           let model = LocalASRModelCatalog.model(modelId, in: catalog) {
            return model.displayName
        }
        return modelId.isEmpty ? MacL10n.string("mac.mode.local", language: language) : modelId
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
