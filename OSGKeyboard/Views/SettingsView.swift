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
    @Environment(\.openURL) private var openURL

    let presentation: SettingsPresentation

    init(presentation: SettingsPresentation = .sheet) {
        self.presentation = presentation
    }

    // Dynamic locale list loaded from SFSpeechRecognizer on first appear.
    @State private var dynamicLocales: [(id: String, onDevice: Bool)] = []
    // v0.2.0: no on-device model manager / pending download state —
    // iOS `SpeechAnalyzer` ships with iOS 26 and needs nothing
    // downloaded.

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
                            SpeechHistoryStore.shared.clearAll()
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
                            appLanguageSection
                            engineSection
                            languageAndPolishSection
                            // v0.2.1: hide provider/api card when the
                            // local engine is active regardless of the
                            // cloud-polish toggle. Local mode is
                            // contractually ASR-only, so provider/model/
                            // base URL/API key controls have no use —
                            // and exposing them invites the user to fill
                            // out a DeepSeek key they can't use.
                            if config.engineMode == "cloud" {
                                providerSection
                                apiSection
                            }
                            if config.engineMode == "local" {
                                localEngineSettingsSection
                            }
                            if presentation == .tab {
                                preferencesSection
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
            // v0.2.0: no on-device model manager to refresh — the
            // iOS ASR backend is always ready.
        }
    }

    // MARK: - App language

    private var appLanguageSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.appLanguage.title")
            Picker("", selection: $config.uiLanguage) {
                ForEach(AppUILanguage.allCases) { language in
                    Text(LocalizedStringKey(language.labelKey)).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .padding(Spacing.md)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Engine

    private var engineSection: some View {
        EnginePickerSection(config: config)
    }

    // MARK: - Language & polish

    private var languageAndPolishSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.languageAndPolish.title")
            VStack(spacing: 0) {
                LocalePickerRow(
                    locales: effectiveLocales,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )
                if config.isPolishScenarioRowVisible {
                    Divider().background(palette.divider)
                    ScenarioPickerRow(config: config, isVisible: true)
                    if config.engineMode == "cloud", config.isTranslationRowVisible {
                        Divider().background(palette.divider)
                        TranslationPickerRow(config: config, isVisible: true)
                    }
                    if config.isCustomPolishScenario {
                        Divider().background(palette.divider)
                        NavigationLink {
                            SystemPromptSettingsView(config: config)
                        } label: {
                            footerNavigationRow(title: "settings.systemPrompt.edit")
                        }
                        .buttonStyle(.plain)
                    }
                }
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

    /// v0.2.1 follow-up: dedicated section for the local engine's
    /// settings (cloud-polish toggle + translation row). Renders only
    /// when `engineMode == "local"` so the cloud-engine user doesn't
    /// see rows that are inert for them. The translation row lives
    /// inside `LocalModelsGroup` so it shares the group's surface card
    /// chrome — see `LocalEngineSettingsRows.swift` for the layout.
    private var localEngineSettingsSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.localEngine.title")
            LocalModelsGroup(config: config)
        }
    }

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

    // MARK: - Language helpers

    /// Falls back to a static list while dynamic locales are loading.
    private var effectiveLocales: [(id: String, onDevice: Bool)] {
        dynamicLocales.isEmpty ? staticLocales : dynamicLocales
    }

    private var staticLocales: [(id: String, onDevice: Bool)] {
        [
            ("auto", false),
            ("zh-Hans", false),
            ("zh-Hant", false),
            ("en-US", false),
            ("ja-JP", false),
            ("ko-KR", false),
        ]
    }

    // MARK: - Dynamic locale loading

    private func loadDynamicLocales() async {
        // Run everything in a background task: `SFSpeechRecognizer.supportedLocales()`
        // can return 100+ locales, and we probe supportsOnDeviceRecognition for each.
        // Creating `SFSpeechRecognizer` instances in a @Sendable closure is
        // safe here; we only read locale metadata (no transcription session).
        let entries: [(id: String, onDevice: Bool)] = await Task.detached(
            priority: .userInitiated
        ) {
            var result: [(id: String, onDevice: Bool)] = [("auto", false)]

            for locale in SFSpeechRecognizer.supportedLocales()
                                             .sorted(by: { $0.identifier < $1.identifier }) {
                let id = locale.identifier
                let onDevice = SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
                result.append((id: id, onDevice: onDevice))
            }
            return result
        }.value

        // .task {} calls us from the main actor, so this assignment is safe.
        dynamicLocales = entries
    }

    // MARK: - Preferences (tab settings only)

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.preferences.title")
            VStack(spacing: 0) {
                HandednessPickerRow(
                    selection: Binding(
                        get: { config.handednessPreference },
                        set: { config.handednessPreference = $0 }
                    )
                )

                Divider().background(palette.divider)

                polishIntensityPreferenceRows

                Divider().background(palette.divider)

                NavigationLink {
                    PersonalDictionaryView()
                } label: {
                    personalDictionaryPreferenceRow
                }
                .buttonStyle(.plain)
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    private var polishIntensityPreferenceRows: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("settings.polishIntensity.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

            Picker("", selection: $config.polishIntensity) {
                ForEach(PolishIntensity.allCases, id: \.self) { intensity in
                    Text(SharedL10n.string(intensity.labelKey, language: config.uiLanguage))
                        .tag(intensity)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)
        }
    }

    private var personalDictionaryPreferenceRow: some View {
        footerNavigationRow(title: "settings.personalDictionary.title")
    }

    // MARK: - Footer links (tab settings only)

    private var footerLinks: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.about.title")
            VStack(spacing: 0) {
                Button {
                    config.hasCompletedOnboarding = false
                    config.onboardingPage = 0
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Text("settings.onboarding.replay")
                            .font(TypeStyle.body)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().background(palette.divider)

                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    footerNavigationRow(title: "settings.privacy.policy")
                }
                .buttonStyle(.plain)
                Divider().background(palette.divider)

                NavigationLink {
                    HelpFeedbackView()
                } label: {
                    footerNavigationRow(title: "settings.link.support")
                }
                .buttonStyle(.plain)
                Divider().background(palette.divider)

                footerExternalLinkRow(
                    title: "settings.link.github",
                    url: LegalLinks.repositoryURL
                )
                Divider().background(palette.divider)

                NavigationLink {
                    OpenSourceLicensesView()
                } label: {
                    footerNavigationRow(title: "settings.link.licenses")
                }
                .buttonStyle(.plain)
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
    }

    private func footerExternalLinkRow(title: LocalizedStringKey, url: URL) -> some View {
        Button {
            openURL(url)
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

    /// In-app disclosure row that pushes a child view onto the
    /// `NavigationStack` rather than opening Safari. Used for the
    /// Third-Party Licenses entry so the system "back" button
    /// returns to Settings.
    private func footerNavigationRow(title: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(title)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
        .contentShape(Rectangle())
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

// MARK: - Handedness picker row

private struct HandednessPickerRow: View {
    @Binding var selection: HandednessPreference

    private var options: [(id: String, label: String)] {
        HandednessPreference.allCases.map { preference in
            (preference.rawValue, AppL10n.string(preference.labelKey))
        }
    }

    var body: some View {
        PickerRow(
            title: AppL10n.string("settings.handedness.title"),
            options: options,
            selection: Binding(
                get: { selection.rawValue },
                set: { newValue in
                    selection = HandednessPreference(rawValue: newValue) ?? .left
                }
            )
        )
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
    @ObservedObject private var config = ProviderConfig.shared

    let locales: [(id: String, onDevice: Bool)]
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
                        let name = label(for: locale.id)
                        if locale.id == selection {
                            Label(name, systemImage: "checkmark")
                        } else if locale.onDevice {
                            Label(name, systemImage: "iphone")
                        } else {
                            Text(name)
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

    private func label(for localeId: String) -> String {
        ASRLocaleLabels.displayName(for: localeId, language: config.uiLanguage)
    }

    private var currentLabel: String {
        label(for: selection)
    }
}
