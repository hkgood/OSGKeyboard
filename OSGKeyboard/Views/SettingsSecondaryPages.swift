// SettingsSecondaryPages.swift
// OSGKeyboard · Main App
//
// Secondary Settings screens: speech recognition, text polish, voice
// session, general preferences, and about. Main Settings stays a
// daily console with summary navigation rows.

import SwiftUI
import OSGKeyboardShared

// MARK: - Navigation row (title + optional summary subtitle)

struct SettingsNavigationRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: LocalizedStringKey
    var subtitle: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.xs)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .settingsListRow()
        .contentShape(Rectangle())
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

struct SpeechRecognitionSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                if config.engineMode == "cloud" {
                    CardSection("settings.asrProvider.title") {
                        CloudProviderSettingsCard {
                            ProviderPickerSection(config: config, role: .asr, showsSurface: false)
                            Divider().background(palette.divider)
                            ASRSettingsCard(config: config, showsSurface: false)
                        }
                    }
                } else {
                    CardSection("settings.localEngine.title") {
                        LocalModelsGroup(config: config)
                    }
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.speechRecognition.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
    }
}

// MARK: - Text polish (LLM)

struct TextPolishSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection("settings.polishProvider.title") {
                    CloudProviderSettingsCard {
                        ProviderPickerSection(config: config, role: .polish, showsSurface: false)
                        Divider().background(palette.divider)
                        APISettingsCard(config: config, showsSurface: false)
                    }
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.textPolish.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
    }
}

// MARK: - Voice session rows (embedded in Daily)

struct VoiceSessionSettingsRows: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    @State private var showActiveFlowSessionAlert = false

    var body: some View {
        VStack(spacing: 0) {
            FlowKeepAliveModePickerRow(
                selection: Binding(
                    get: { config.flowKeepAliveMode },
                    set: { applyKeepAliveModeChange($0) }
                )
            )

            if config.flowKeepAliveMode == .liveActivity {
                Divider().background(palette.divider)

                FlowInactivityPickerRow(
                    selection: Binding(
                        get: { config.flowInactivityDuration },
                        set: { config.flowInactivityDuration = $0 }
                    )
                )

                Divider().background(palette.divider)

                Toggle(isOn: $config.flowSkipAppSwitch) {
                    flowSkipAppSwitchLabel
                }
                .tint(palette.accent)
                .settingsListRow()
            } else {
                Divider().background(palette.divider)

                Text("settings.flow.keepAlive.pictureInPicture.note")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsListRow()
            }
        }
        .alert("settings.flow.keepAlive.activeSession.title", isPresented: $showActiveFlowSessionAlert) {
            Button("common.done", role: .cancel) {}
        } message: {
            Text("settings.flow.keepAlive.activeSession.message")
        }
    }

    private var flowSkipAppSwitchLabel: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("settings.flow.skipAppSwitch.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Text("settings.flow.skipAppSwitch.subtitle")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private func applyKeepAliveModeChange(_ newMode: FlowKeepAliveMode) {
        guard newMode != config.flowKeepAliveMode else { return }
        if FlowSessionBridge.isSessionActive() {
            showActiveFlowSessionAlert = true
            return
        }
        config.flowKeepAliveMode = newMode
    }
}

// MARK: - General (appearance, keyboard, sync)

struct GeneralSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection("settings.general.appearanceLanguage.title") {
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

                CardSection("settings.general.keyboard.title") {
                    VStack(spacing: 0) {
                        HandednessPickerRow(
                            selection: Binding(
                                get: { config.handednessPreference },
                                set: { config.handednessPreference = $0 }
                            )
                        )
                        Divider().background(palette.divider)
                        CursorDragNavigationToggleRow(
                            isOn: $config.cursorDragNavigationEnabled
                        )
                    }
                    .surfaceCard()
                }

                CardSection("settings.general.sync.title") {
                    VStack(spacing: 0) {
                        SettingsICloudSyncRow()
                    }
                    .surfaceCard()
                }
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.general.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
    }
}

// MARK: - About

struct AboutSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.openURL) private var openURL
    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            CardPageContent {
                CardSection("settings.about.title") {
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
                                Text("settings.link.github")
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
        .navigationTitle("settings.about.title")
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBarWhenPushed()
    }
}
