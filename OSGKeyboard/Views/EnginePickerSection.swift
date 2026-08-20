// EnginePickerSection.swift
// OSGKeyboard · Main App
//
// Global AI service source. ASR locality is selected separately in the
// speech-recognition provider list when the user supplies credentials.

import OSGKeyboardShared
import SwiftUI

struct EnginePickerSection<ConfigurationRows: View>: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @ObservedObject var config: ProviderConfig
    @State private var showsManagedCloudConsent = false
    private let configurationRows: ConfigurationRows

    init(
        config: ProviderConfig,
        @ViewBuilder configurationRows: () -> ConfigurationRows
    ) {
        self.config = config
        self.configurationRows = configurationRows()
    }

    var body: some View {
        CardSection("settings.aiService.title") {
            VStack(spacing: 0) {
                serviceOptionRow(
                    source: .managed,
                    title: AppL10n.string("settings.aiService.credits.title"),
                    subtitle: AppL10n.string(
                        accountSession.isSignedIn
                            ? "settings.aiService.credits.subtitle"
                            : "settings.aiService.credits.signIn"
                    )
                )
                Divider().background(palette.divider)
                serviceOptionRow(
                    source: .byok,
                    title: AppL10n.string("settings.aiService.byok.title"),
                    subtitle: AppL10n.string("settings.aiService.byok.subtitle")
                )
                if config.credentialSource == .byok {
                    configurationRows
                }
            }
            .surfaceCard()
        }
        .alert(
            "settings.aiService.credits.consent.title",
            isPresented: $showsManagedCloudConsent
        ) {
            Button("common.cancel", role: .cancel) {}
            Button("settings.aiService.credits.consent.accept") {
                config.hasAcknowledgedCloudSharing = true
                activateManagedService()
            }
            .accessibilityIdentifier("settings.aiService.credits.consent.accept")
        } message: {
            Text("settings.aiService.credits.consent.message")
        }
    }

    private func serviceOptionRow(
        source: CredentialSource,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = config.credentialSource == source
        return Button {
            guard config.credentialSource != source else { return }
            selectSource(source)
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeStyle.body)
                        .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                    Text(subtitle)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.aiService.\(source.rawValue)")
        .accessibilityValue(isSelected ? "selected" : "notSelected")
        .disabled(
            accountSession.operation != nil
                || (source == .managed && !accountSession.isSignedIn)
        )
    }

    private func selectSource(_ source: CredentialSource) {
        switch source {
        case .managed:
            if config.hasAcknowledgedCloudSharing {
                activateManagedService()
            } else {
                showsManagedCloudConsent = true
            }
        case .byok:
            withAnimation(Motion.quick) {
                config.credentialSource = .byok
            }
            Task { await accountSession.clearManagedGateway() }
        }
    }

    private func activateManagedService() {
        Task {
            if await accountSession.prepareManagedGateway() {
                withAnimation(Motion.quick) {
                    config.engineMode = "cloud"
                    config.modeId = "polish"
                    config.credentialSource = .managed
                }
            }
        }
    }
}

extension EnginePickerSection where ConfigurationRows == EmptyView {
    init(config: ProviderConfig) {
        self.init(config: config) {
            EmptyView()
        }
    }
}
