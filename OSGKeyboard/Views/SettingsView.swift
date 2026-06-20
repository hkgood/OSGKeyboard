// SettingsView.swift
// OSGKeyboard · Main App
//
// Sheet that hosts the API configuration. Single scrollable column, every
// field earns its space.

import SwiftUI
import Speech
import OSGKeyboardShared

enum SettingsPresentation {
    case tab
    case sheet
}

struct SettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config = ProviderConfig.shared
    @Environment(\.dismiss) private var dismiss
    @State private var safariURL: URL?

    let presentation: SettingsPresentation

    init(presentation: SettingsPresentation = .sheet) {
        self.presentation = presentation
    }

    // Dynamic locale list loaded from SFSpeechRecognizer on first appear.
    @State private var dynamicLocales: [(id: String, label: String, onDevice: Bool)] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PageHeaderRow(title: "settings.title") {
                    HStack(spacing: Spacing.xs) {
                        PageHeaderConfirmButton(
                            systemImage: "arrow.counterclockwise",
                            accessibilityLabel: "settings.reset.confirm",
                            confirmTitle: "settings.reset.title",
                            confirmMessage: "settings.reset.message",
                            confirmActionTitle: "common.reset"
                        ) {
                            config.reset()
                        }
                        if presentation == .sheet {
                            Button("common.done") { dismiss() }
                                .font(TypeStyle.headline)
                                .foregroundStyle(palette.accent)
                                .frame(minHeight: 44)
                        }
                    }
                }

                ZStack {
                    palette.background.ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                            engineSection
                            if config.engineMode == "cloud" {
                                providerSection
                                apiSection
                            }
                            languageSection
                            if config.engineMode == "cloud" {
                                promptSection
                            }
                            if presentation == .tab {
                                footerLinks
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.md)
                        .padding(.bottom, presentation == .tab ? 100 : Spacing.lg)
                    }
                }
            }
            .background(palette.background)
            .toolbar(.hidden, for: .navigationBar)
            .task { await loadDynamicLocales() }
            .sheet(item: $safariURL) { url in
                SafariSheet(url: url)
            }
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        EnginePickerSection(config: config)
    }

    // MARK: - Provider

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.provider.title")
            ProviderPickerSection(config: config)
        }
    }

    // MARK: - API

    private var apiSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.api.title")
            APISettingsCard(config: config)
        }
    }

    // MARK: - Language (ASR + mode)

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.language.title")
            VStack(spacing: 0) {
                if config.engineMode == "cloud" {
                    PickerRow(
                        title: NSLocalizedString("settings.mode.title", comment: ""),
                        options: modeOptions,
                        selection: Binding(
                            get: { config.modeId },
                            set: { config.modeId = $0 }
                        )
                    )
                    Divider().background(palette.divider)
                    asrEngineRow
                    Divider().background(palette.divider)
                }
                LocalePickerRow(
                    locales: effectiveLocales,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )

            // Legacy legend block: kept for UI compatibility, but with
            // iOS 26 as minimum target this branch never executes.
            if #unavailable(iOS 26) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "iphone")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                    Text("settings.legend.onDevice")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Image(systemName: "cloud")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.warning)
                    Text("settings.legend.cloudFallback")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Spacing.xs)
            }
        }
    }

    /// ASR engine row. With iOS 26 as the deployment target, the
    /// only ASR backend is `SpeechAnalyzer` and it is always fully
    /// on-device — so this row is now a static badge rather than a
    /// toggle. The old cloud-fallback toggle is gone.
    private var asrEngineRow: some View {
        HStack(spacing: Spacing.sm) {
            Text("settings.engineRow.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "iphone.badge.checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.accent)
                Text("settings.engineBadge.ios26")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.accent)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 4)
            .background(palette.accent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    /// Falls back to a static list while dynamic locales are loading.
    private var effectiveLocales: [(id: String, label: String, onDevice: Bool)] {
        dynamicLocales.isEmpty ? staticLocales : dynamicLocales
    }

    private var staticLocales: [(id: String, label: String, onDevice: Bool)] {
        [
            ("auto",     NSLocalizedString("locale.auto", comment: ""),     false),
            ("zh-Hans",  NSLocalizedString("locale.zh-Hans", comment: ""),  false),
            ("zh-Hant",  NSLocalizedString("locale.zh-Hant", comment: ""),  false),
            ("en-US",    NSLocalizedString("locale.en-US", comment: ""),    false),
            ("ja-JP",    NSLocalizedString("locale.ja-JP", comment: ""),    false),
            ("ko-KR",    NSLocalizedString("locale.ko-KR", comment: ""),    false)
        ]
    }

    private var modeOptions: [(id: String, label: String)] {
        [
            ("off",        NSLocalizedString("settings.mode.off", comment: "")),
            ("transcribe", NSLocalizedString("settings.mode.transcribe", comment: "")),
            ("polish",     NSLocalizedString("settings.mode.polish", comment: ""))
        ]
    }

    // MARK: - Dynamic locale loading

    private func loadDynamicLocales() async {
        // Run everything in a background task: `SFSpeechRecognizer.supportedLocales()`
        // can return 100+ locales, and we probe supportsOnDeviceRecognition for each.
        // Creating `SFSpeechRecognizer` instances in a @Sendable closure is
        // safe here; we only read locale metadata (no transcription session).
        let entries: [(id: String, label: String, onDevice: Bool)] = await Task.detached(
            priority: .userInitiated
        ) {
            var result: [(id: String, label: String, onDevice: Bool)] = []
            result.append(("auto", NSLocalizedString("locale.auto", comment: ""), false))

            let currentLocale = Locale.current  // snapshot on background thread is fine
            for locale in SFSpeechRecognizer.supportedLocales()
                                             .sorted(by: { $0.identifier < $1.identifier }) {
                let id = locale.identifier
                let onDevice = SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
                // localizedString on Locale.current gives the name in the app's UI language.
                let displayName = currentLocale.localizedString(forIdentifier: id) ?? id
                result.append((id: id, label: displayName, onDevice: onDevice))
            }
            return result
        }.value

        // .task {} calls us from the main actor, so this assignment is safe.
        dynamicLocales = entries
    }

    // MARK: - Prompt

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            HStack {
                sectionHeader("settings.systemPrompt.title")
                Spacer()
                Button("common.reset") { config.systemPrompt = config.defaultSystemPrompt }
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.accent)
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                TextEditor(text: $config.systemPrompt)
                    .font(TypeStyle.mono)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 140)
                    .padding(Spacing.xs)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
            }
            .cardSurface()
        }
    }

    // MARK: - Footer links (tab settings only)

    private var footerLinks: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.about.title")
            VStack(spacing: 0) {
                if let url = LegalLinks.privacyPolicyURL {
                    footerLinkRow(title: "settings.privacy.policy", url: url)
                    Divider().background(palette.divider)
                }
                footerLinkRow(
                    title: "settings.link.github",
                    url: URL(string: "https://github.com/hkgood/OSGKeyboard")!
                )
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    private func footerLinkRow(title: LocalizedStringKey, url: URL) -> some View {
        Button {
            safariURL = url
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                MaterialIcon(name: .openInNew, size: 18)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Header

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(TypeStyle.caption2)
            .foregroundStyle(palette.textSecondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Picker row (generic)

private struct PickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: String
    let options: [(id: String, label: String)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text(title)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                ForEach(options, id: \.id) { o in
                    Button {
                        selection = o.id
                    } label: {
                        if o.id == selection {
                            Label(o.label, systemImage: "checkmark")
                        } else {
                            Text(o.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(currentLabel)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    private var currentLabel: String {
        options.first(where: { $0.id == selection })?.label ?? "—"
    }
}

// MARK: - Locale picker row (with on-device indicator)

private struct LocalePickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let locales: [(id: String, label: String, onDevice: Bool)]
    @Binding var selection: String

    var body: some View {
        HStack {
            Text("settings.asrLocale")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                ForEach(locales, id: \.id) { locale in
                    Button {
                        selection = locale.id
                    } label: {
                        // iOS Menu converts SwiftUI Label to UIAction (title + image).
                        // Using Label keeps checkmark + on-device icon both visible.
                        if locale.id == selection {
                            Label(locale.label, systemImage: "checkmark")
                        } else if locale.onDevice {
                            Label(locale.label, systemImage: "iphone")
                        } else {
                            Text(locale.label)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    // On-device badge for the currently selected locale.
                    if let current = locales.first(where: { $0.id == selection }), current.onDevice {
                        Image(systemName: "iphone")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.accent)
                    }
                    Text(currentLabel)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    private var currentLabel: String {
        locales.first(where: { $0.id == selection })?.label ?? "—"
    }
}
