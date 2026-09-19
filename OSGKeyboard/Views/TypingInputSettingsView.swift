// TypingInputSettingsView.swift
// OSGKeyboard · Main App
//
// Schema and opt-in fuzzy-pinyin settings. Changing fuzzy pairs triggers
// host-side redeployment; the keyboard extension never compiles schemas.

import OSGKeyboardShared
import SwiftUI

struct TypingInputSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var configuration = TypingInputConfiguration.shared
    @ObservedObject private var deployment = RimeDeploymentController.shared

    private var isDeploying: Bool { deployment.isDeploying }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CardLayoutMetrics.sectionSpacing) {
                settingsSection(
                    title: AppL10n.string(
                        "settings.typingInput.schema.section",
                        language: config.uiLanguage
                    )
                ) {
                    schemaOptionsCard
                }

                settingsSection(
                    title: AppL10n.string(
                        "settings.typingInput.fuzzy.section",
                        language: config.uiLanguage
                    ),
                    footer: AppL10n.string(
                        "settings.typingInput.fuzzy.footer",
                        language: config.uiLanguage
                    )
                ) {
                    fuzzyPairsCard
                }

                settingsSection(
                    title: AppL10n.string(
                        "settings.typingInput.resources.section",
                        language: config.uiLanguage
                    )
                ) {
                    resourcesCard
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .scrollClipDisabled()
        .background(palette.background)
        .navigationTitle(AppL10n.string("settings.typingInput.title", language: config.uiLanguage))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var schemaOptionsCard: some View {
        VStack(spacing: 0) {
            ForEach(TypingInputSchema.allCases) { schema in
                schemaOptionRow(schema)

                if schema != TypingInputSchema.allCases.last {
                    Divider().background(palette.divider)
                }
            }
        }
        .surfaceCard()
    }

    private func schemaOptionRow(_ schema: TypingInputSchema) -> some View {
        let isSelected = configuration.schema == schema
        return Button {
            guard !isSelected else { return }
            configuration.schema = schema
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(AppL10n.string(schema.labelKey, language: config.uiLanguage))
                    .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(TypeStyle.footnote.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "selected" : "notSelected")
    }

    private var fuzzyPairsCard: some View {
        VStack(spacing: 0) {
            ForEach(PinyinFuzzyPair.allCases) { pair in
                Toggle(
                    isOn: Binding(
                        get: { configuration.fuzzyPairs.contains(pair) },
                        set: { enabled in
                            configuration.setFuzzyPair(pair, enabled: enabled)
                            deployUpdatedSchemas()
                        }
                    )
                ) {
                    Text(pair.displayName)
                        .font(TypeStyle.body)
                }
                .settingsListRow()

                if pair != PinyinFuzzyPair.allCases.last {
                    Divider().background(palette.divider)
                }
            }
        }
        .surfaceCard()
    }

    private var resourcesCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppL10n.string("settings.typingInput.resources.status", language: config.uiLanguage))
                    .font(TypeStyle.body)
                Spacer()
                if isDeploying {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(statusText)
                        .font(TypeStyle.body)
                        .foregroundStyle(
                            hasDeploymentError ? palette.danger : palette.textSecondary
                        )
                }
            }
            .settingsListRow()

            Divider().background(palette.divider)

            Button(AppL10n.string("settings.typingInput.resources.redeploy", language: config.uiLanguage)) {
                deployUpdatedSchemas()
            }
            .font(TypeStyle.body)
            .settingsListRow()
            .disabled(isDeploying)
        }
        .surfaceCard()
    }

    private func settingsSection<Content: View>(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: SettingsListMetrics.sectionLabelSpacing) {
            if let title {
                Text(title)
                    .cardSectionLabel()
            }
            content()
            if let footer {
                Text(footer)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var hasDeploymentError: Bool {
        if case .failed = deployment.status { return true }
        return false
    }

    private var statusText: String {
        if case .failed(let message) = deployment.status { return message }
        return AppL10n.string(
            RimeResourceInstaller.isReady
                ? "settings.typingInput.resources.ready"
                : "settings.typingInput.resources.pending",
            language: config.uiLanguage
        )
    }

    private func deployUpdatedSchemas() {
        deployment.deployNow(force: true, reason: "settings.typingInput")
    }
}
