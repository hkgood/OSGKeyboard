// SettingsSecondaryPages.swift
// OSGKeyboard · Main App
//
// Secondary Settings screens: speech recognition, text polish, voice
// session, general preferences, and about. Main Settings stays a
// daily console with summary navigation rows.

import OSGKeyboardShared
import SwiftUI

// MARK: - Navigation row (title + optional trailing summary before chevron)

struct SettingsNavigationRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    private let localizedTitle: String?
    private let resolvedTitle: String?
    var subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.localizedTitle = title
        self.resolvedTitle = nil
        self.subtitle = subtitle
    }

    /// Prefers in-app language via an already-resolved string (`AppL10n`).
    init(titleText: String, subtitle: String? = nil) {
        self.localizedTitle = nil
        self.resolvedTitle = titleText
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if let resolvedTitle {
                Text(resolvedTitle)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
            } else if let localizedTitle {
                Text(AppL10n.string(localizedTitle))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: Spacing.xs)
            // Trailing summary — same slot as SettingsVersionRow's value.
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .settingsListRow()
        .contentShape(Rectangle())
    }
}

/// Version / build row for Settings home (below About). Opens release notes.
struct SettingsVersionRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared

    var body: some View {
        Button {
            ReleaseNotesController.shared.presentManually()
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(AppL10n.string("settings.version.title", language: config.uiLanguage))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Spacing.xs)
                Text(AppVersionDisplay.detailedLabel)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(AppL10n.string("releaseNotes.openHint", language: config.uiLanguage))
    }
}

// MARK: - Config entry summaries (shown on Settings home)

enum SettingsConfigSummary {
    static func speechRecognition(config: ProviderConfig) -> String {
        if config.engineMode == "local" {
            return SharedL10n.string(
                "engine.asr.appleSpeech",
                language: config.uiLanguage
            )
        }

        let providerName = ProviderDisplayName.name(
            for: config.asrProviderId,
            language: config.uiLanguage
        )
        let trimmedModel = config.asrModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty {
            return providerName
        }
        return "\(providerName) · \(trimmedModel)"
    }

    static func textPolish(config: ProviderConfig) -> String {
        let providerName = ProviderDisplayName.name(
            for: config.providerId,
            language: config.uiLanguage
        )
        let trimmedModel = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.isEmpty {
            return providerName
        }
        return "\(providerName) · \(trimmedModel)"
    }

}

// MARK: - Shared cloud provider card chrome

private struct CloudProviderSettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .surfaceCard()
    }
}

// MARK: - Speech recognition (ASR / local engine)

struct AppleASRPickerRow: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        Toggle(isOn: usesAppleRecognition) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(AppL10n.string("settings.asr.apple.title"))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Text(AppL10n.string("settings.asr.apple.subtitle"))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .tint(palette.accent)
        .settingsListRow()
    }

    private var usesAppleRecognition: Binding<Bool> {
        Binding(
            get: { config.engineMode == "local" },
            set: { isEnabled in
                withAnimation(Motion.quick) {
                    config.engineMode = isEnabled ? "local" : "cloud"
                    if !isEnabled {
                        config.modeId = "polish"
                    }
                }
            }
        )
    }
}

struct SpeechRecognitionSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.asrProvider.title")) {
                    CloudProviderSettingsCard {
                        AppleASRPickerRow(config: config)

                        if config.engineMode == "cloud" {
                            Divider().background(palette.divider)
                            ProviderPickerSection(
                                config: config,
                                role: .asr,
                                showsSurface: false
                            )
                            Divider().background(palette.divider)
                            ASRSettingsCard(config: config, showsSurface: false)
                        }
                    }
                }

                if config.engineMode == "local" {
                    CardSection(title: AppL10n.string("settings.localEngine.title")) {
                        LocalModelsGroup(config: config)
                    }
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.speechRecognition.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Text polish (LLM)

struct TextPolishSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.polishProvider.title")) {
                    CloudProviderSettingsCard {
                        ProviderPickerSection(config: config, role: .polish, showsSurface: false)
                        Divider().background(palette.divider)
                        APISettingsCard(config: config, showsSurface: false)
                    }
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.textPolish.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - General (appearance, keyboard, sync)

struct GeneralSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig
    @ObservedObject private var typingConfiguration = TypingInputConfiguration.shared

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.general.appearanceLanguage.title")) {
                    VStack(spacing: 0) {
                        AppLanguagePickerRow(
                            selection: Binding(
                                get: { config.uiLanguage },
                                set: { config.uiLanguage = $0 }
                            )
                        )
                        Divider().background(palette.divider)
                        AppearancePickerRow()
                    }
                    .surfaceCard()
                }

                CardSection(title: AppL10n.string("settings.general.keyboard.title")) {
                    VStack(spacing: 0) {
                        DefaultInputModePickerRow(
                            selection: $typingConfiguration.defaultInputMode
                        )

                        Divider().background(palette.divider)

                        RememberLastSurfaceToggleRow(
                            isOn: $typingConfiguration.rememberLastSurface
                        )

                        Divider().background(palette.divider)

                        NavigationLink {
                            TypingInputSettingsView()
                        } label: {
                            SettingsNavigationRow(
                                titleText: AppL10n.string(
                                    "settings.typingInput.title",
                                    language: config.uiLanguage
                                )
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().background(palette.divider)

                        HandednessPickerRow(
                            selection: Binding(
                                get: { config.handednessPreference },
                                set: { config.handednessPreference = $0 }
                            )
                        )
                        Divider().background(palette.divider)
                        KeyboardHapticPickerRow(
                            selection: Binding(
                                get: { config.keyboardHapticIntensity },
                                set: { config.keyboardHapticIntensity = $0 }
                            )
                        )
                    }
                    .surfaceCard()
                }

                CardSection(title: AppL10n.string("settings.general.sync.title")) {
                    VStack(spacing: 0) {
                        SettingsICloudSyncRow()
                    }
                    .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.general.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI Agent

struct AIAgentSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.aiAgent.responseLength.section")) {
                    VStack(spacing: 0) {
                        AIResponseLengthPickerRow(config: config)
                        Divider().background(palette.divider)
                        Toggle(isOn: $config.multipleReplyVariantsEnabled) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(AppL10n.string("settings.aiAgent.multipleReplies.title"))
                                    .font(TypeStyle.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text(AppL10n.string("settings.aiAgent.multipleReplies.description"))
                                    .font(TypeStyle.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                        .tint(palette.accent)
                        .settingsListRow()
                        .accessibilityIdentifier(
                            "settings.aiAgent.multipleReplies.toggle"
                        )
                    }
                    .surfaceCard()
                }
                CardSection(title: AppL10n.string("settings.aiAgent.autoMode.section")) {
                    VStack(spacing: 0) {
                        autoModeToggle(
                            isOn: $config.clipboardAutoModeEnabled,
                            titleKey: "settings.aiAgent.autoMode.title",
                            descriptionKey: "settings.aiAgent.autoMode.description",
                            identifier: "settings.aiAgent.autoMode.toggle"
                        )
                        Divider().background(palette.divider)
                        autoModeToggle(
                            isOn: $config.clipboardAutoTranslateEnabled,
                            titleKey: "settings.aiAgent.autoTranslate.title",
                            descriptionKey: "settings.aiAgent.autoTranslate.description",
                            identifier: "settings.aiAgent.autoTranslate.toggle"
                        )
                        Divider().background(palette.divider)
                        autoModeToggle(
                            isOn: $config.clipboardAutoEmailReplyEnabled,
                            titleKey: "settings.aiAgent.autoEmailReply.title",
                            descriptionKey: "settings.aiAgent.autoEmailReply.description",
                            identifier: "settings.aiAgent.autoEmailReply.toggle"
                        )
                    }
                    .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.aiAgent.title", language: config.uiLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func autoModeToggle(
        isOn: Binding<Bool>,
        titleKey: String,
        descriptionKey: String,
        identifier: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(AppL10n.string(titleKey))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Text(AppL10n.string(descriptionKey))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .tint(palette.accent)
        .settingsListRow()
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Clipboard

struct ClipboardSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var config: ProviderConfig
    @ObservedObject private var history = ClipboardHistoryStore.shared
    @State private var showClearConfirmation = false
    @StateObject private var pasteAccess = PasteAccessController()

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.clipboard.section")) {
                    VStack(spacing: 0) {
                        Toggle(isOn: $config.clipboardHistoryEnabled) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(AppL10n.string("settings.clipboard.history.title"))
                                    .font(TypeStyle.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text(AppL10n.string("settings.clipboard.history.footer"))
                                    .font(TypeStyle.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                        .tint(palette.accent)
                        .settingsListRow()
                    }
                    .surfaceCard()
                }

                // iOS asks per read unless the user flips the durable
                // "Paste from Other Apps" permission to Allow.
                CardSection(title: AppL10n.string("settings.clipboard.paste.section")) {
                    VStack(spacing: 0) {
                        HStack(alignment: .center, spacing: Spacing.sm) {
                            Text(AppL10n.string("settings.clipboard.paste.body"))
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if pasteAccess.isVerified {
                                Label(
                                    AppL10n.string("settings.clipboard.paste.verified"),
                                    systemImage: "checkmark.circle.fill"
                                )
                                .font(TypeStyle.caption)
                                .foregroundStyle(palette.accent)
                                .fixedSize()
                                .accessibilityIdentifier("settings.clipboard.paste.verified")
                            }
                        }
                        .settingsListRow()

                        if !pasteAccess.isVerified {
                            Divider().background(palette.divider)

                            Button {
                                pasteAccess.verify()
                            } label: {
                                SettingsNavigationRow(
                                    titleText: AppL10n.string(
                                        "settings.clipboard.paste.request",
                                        language: config.uiLanguage
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.clipboard.paste.verify")

                            if pasteAccess.needsRecovery {
                                Divider().background(palette.divider)

                                Button {
                                    AppPermissions.openSystemSettings()
                                } label: {
                                    SettingsNavigationRow(
                                        titleText: AppL10n.string(
                                            "settings.clipboard.paste.open",
                                            language: config.uiLanguage
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("settings.clipboard.paste.openSettings")
                            }
                        }
                    }
                    .surfaceCard()
                }

                CardSection(title: AppL10n.string("settings.clipboard.storage.section")) {
                    VStack(spacing: 0) {
                        Text(AppL10n.string("settings.clipboard.storage.body"))
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .settingsListRow()

                        Divider().background(palette.divider)

                        Button(role: .destructive) {
                            showClearConfirmation = true
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text(AppL10n.string("settings.clipboard.clear.button"))
                                    .font(TypeStyle.body)
                                Spacer(minLength: Spacing.xs)
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(palette.danger)
                            .settingsListRow()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(history.entries.isEmpty)
                        .opacity(history.entries.isEmpty ? 0.45 : 1)
                    }
                    .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.clipboard.title", language: config.uiLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            AppL10n.string("settings.clipboard.clear.title"),
            isPresented: $showClearConfirmation
        ) {
            Button(AppL10n.string("common.cancel"), role: .cancel) {}
            Button(AppL10n.string("settings.clipboard.clear.confirm"), role: .destructive) {
                history.clearAll()
                ClipboardReplyFeedbackStore.shared.clear()
            }
        } message: {
            Text(AppL10n.string("settings.clipboard.clear.message"))
        }
        .alert(
            AppL10n.string("clipboard.paste.noText.title", language: config.uiLanguage),
            isPresented: $pasteAccess.showNoTextAlert
        ) {
            Button(AppL10n.string("common.done")) { pasteAccess.showNoTextAlert = false }
        } message: {
            Text(AppL10n.string("clipboard.paste.noText.message", language: config.uiLanguage))
        }
        .onAppear {
            history.reload()
            pasteAccess.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            pasteAccess.refresh(clearRecovery: true)
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var analytics: AnalyticsHostService
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection(title: AppL10n.string("settings.analytics.section")) {
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle(
                            isOn: Binding(
                                get: { analytics.isEnabled },
                                set: { analytics.setEnabled($0) }
                            )
                        ) {
                            Text(AppL10n.string("settings.analytics.title"))
                                .font(TypeStyle.body)
                                .foregroundStyle(palette.textPrimary)
                        }
                        .tint(palette.accent)
                        .settingsListRow()

                        Divider().background(palette.divider)

                        Text(AppL10n.string("settings.analytics.description"))
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .settingsListRow()
                    }
                    .surfaceCard()
                }

                CardSection(title: AppL10n.string("settings.about.title")) {
                    VStack(spacing: 0) {
                        Button {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                config.hasCompletedOnboarding = false
                                config.onboardingPage = 0
                            }
                        } label: {
                            SettingsNavigationRow(title: "settings.onboarding.replay")
                        }
                        .buttonStyle(.plain)

                        Divider().background(palette.divider)

                        NavigationLink {
                            PrivacyPolicyView()
                        } label: {
                            SettingsNavigationRow(title: "settings.privacy.policy")
                        }
                        .buttonStyle(.plain)

                        Divider().background(palette.divider)

                        NavigationLink {
                            HelpFeedbackView()
                        } label: {
                            SettingsNavigationRow(title: "settings.link.support")
                        }
                        .buttonStyle(.plain)

                        Divider().background(palette.divider)

                        Button {
                            openURL(LegalLinks.repositoryURL)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Text(AppL10n.string("settings.link.github"))
                                    .font(TypeStyle.body)
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                MaterialIcon(name: .openInNew, size: 18)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .settingsListRow()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider().background(palette.divider)

                        NavigationLink {
                            OpenSourceLicensesView()
                        } label: {
                            SettingsNavigationRow(title: "settings.link.licenses")
                        }
                        .buttonStyle(.plain)
                    }
                    .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle(AppL10n.string("settings.about.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            analytics.refreshEnabledState()
        }
    }
}
