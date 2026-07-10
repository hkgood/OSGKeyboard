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
    @State private var showResetConfirmation = false
    // v0.2.0: no on-device model manager / pending download state —
    // iOS `SpeechAnalyzer` ships with iOS 26 and needs nothing
    // downloaded.

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        languageAndPolishSection
                        dictionaryAndPolishSection
                        flowSessionSection
                        engineSection
                        polishProviderSection
                        polishApiSection
                        if config.engineMode == "cloud" {
                            asrProviderSection
                            asrApiSection
                        }
                        if config.engineMode == "local" {
                            localEngineSettingsSection
                        }
                        if presentation == .tab {
                            footerLinks
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .modifier(SettingsScrollBottomPadding(presentation: presentation))
                }
            }
            .background(palette.background)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("settings.reset.confirm")
                    .confirmationDialog(
                        "settings.reset.title",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("common.reset", role: .destructive) {
                            config.reset()
                            SpeechHistoryStore.shared.clearAll()
                        }
                        Button("common.cancel", role: .cancel) {}
                    } message: {
                        Text("settings.reset.message")
                    }
                }
                if presentation == .sheet {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { dismiss() }
                    }
                }
            }
            .task { await loadDynamicLocales() }
            // v0.2.0: no on-device model manager to refresh — the
            // iOS ASR backend is always ready.
        }
    }

    // MARK: - Flow session

    private var flowSessionSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.flow.title")
            VStack(spacing: 0) {
                Toggle(isOn: $config.flowSkipAppSwitch) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("settings.flow.skipAppSwitch.title")
                            .font(TypeStyle.body)
                            .foregroundStyle(palette.textPrimary)
                        Text("settings.flow.skipAppSwitch.subtitle")
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                .tint(palette.accent)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(minHeight: SettingsListMetrics.singleLineMinHeight)

                Divider().background(palette.divider)

                FlowInactivityPickerRow(
                    selection: Binding(
                        get: { config.flowInactivityDuration },
                        set: { config.flowInactivityDuration = $0 }
                    )
                )
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
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
            sectionHeader("settings.preferences.title")
            VStack(spacing: 0) {
                AppLanguagePickerRow(
                    selection: Binding(
                        get: { config.uiLanguage },
                        set: { config.uiLanguage = $0 }
                    )
                )

                Divider().background(palette.divider)

                LocalePickerRow(
                    locales: effectiveLocales,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )

                Divider().background(palette.divider)

                HandednessPickerRow(
                    selection: Binding(
                        get: { config.handednessPreference },
                        set: { config.handednessPreference = $0 }
                    )
                )

                Divider().background(palette.divider)

                cursorDragNavigationToggleRow

                Divider().background(palette.divider)

                SettingsICloudSyncRow()
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
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

    // MARK: - Dictionary & polish

    private var dictionaryAndPolishSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.dictionaryAndPolish.title")
            VStack(spacing: 0) {
                polishIntensityPreferenceRows

                Divider().background(palette.divider)

                TranslationPickerRow(config: config, isVisible: config.isTranslationRowVisible)

                Divider().background(palette.divider)

                PersonalDictionaryICloudSyncRow()
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
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

    private var polishProviderSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.polishProvider.title")
            Text("settings.polishProvider.subtitle")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ProviderPickerSection(config: config, role: .polish)
        }
    }

    private var asrProviderSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.asrProvider.title")
            Text("settings.asrProvider.subtitle")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ProviderPickerSection(config: config, role: .asr)
        }
    }

    private var polishApiSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.polishApi.title")
            APISettingsCard(config: config)
        }
    }

    private var asrApiSection: some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            sectionHeader("settings.asrApi.title")
            ASRSettingsCard(config: config)
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

    // MARK: - Preference row helpers

    private var polishIntensityPreferenceRows: some View {
        // 与「惯用手」一致的右侧下拉菜单行样式，保持偏好设置卡片内各行风格统一。
        PickerRow(
            title: AppL10n.string("settings.polishIntensity.title"),
            options: PolishIntensity.allCases.map { intensity in
                (intensity.rawValue, SharedL10n.string(intensity.labelKey, language: config.uiLanguage))
            },
            selection: Binding(
                get: { config.polishIntensity.rawValue },
                set: { newValue in
                    config.polishIntensity = PolishIntensity(rawValue: newValue) ?? .medium
                }
            )
        )
    }

    private var cursorDragNavigationToggleRow: some View {
        Toggle(isOn: $config.cursorDragNavigationEnabled) {
            Text("settings.cursorDragNavigation.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
        }
        .tint(palette.accent)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
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

// MARK: - Tab dock bottom padding (tab root only)

private struct SettingsScrollBottomPadding: ViewModifier {
    let presentation: SettingsPresentation

    func body(content: Content) -> some View {
        if presentation == .tab {
            content.tabBarScrollBottomPadding()
        } else {
            content.padding(.bottom, Spacing.lg)
        }
    }
}

// MARK: - App language picker row

private struct AppLanguagePickerRow: View {
    @Binding var selection: AppUILanguage

    private var options: [(id: String, label: String)] {
        AppUILanguage.allCases.map { language in
            (language.rawValue, AppL10n.string(language.labelKey))
        }
    }

    var body: some View {
        PickerRow(
            title: AppL10n.string("settings.appLanguage.title"),
            options: options,
            selection: Binding(
                get: { selection.rawValue },
                set: { newValue in
                    selection = AppUILanguage(rawValue: newValue) ?? .auto
                }
            )
        )
    }
}

// MARK: - Flow inactivity picker row

private struct FlowInactivityPickerRow: View {
    @Binding var selection: FlowInactivityDuration

    private var options: [(id: String, label: String)] {
        FlowInactivityDuration.allCases.map { duration in
            (duration.rawValue, AppL10n.string(duration.labelKey))
        }
    }

    var body: some View {
        PickerRow(
            title: AppL10n.string("settings.flow.inactivity.title"),
            options: options,
            selection: Binding(
                get: { selection.rawValue },
                set: { newValue in
                    selection = FlowInactivityDuration(rawValue: newValue) ?? .default
                }
            )
        )
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
