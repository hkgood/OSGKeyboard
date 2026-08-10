// TypingInputSettingsView.swift
// OSGKeyboard · Main App
//
// Schema and opt-in fuzzy-pinyin settings. Changing fuzzy pairs triggers
// host-side redeployment; the keyboard extension never compiles schemas.

import SwiftUI
import OSGKeyboardShared

struct TypingInputSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var configuration = TypingInputConfiguration.shared
    @ObservedObject private var deployment = RimeDeploymentController.shared

    private var isDeploying: Bool { deployment.isDeploying }

    var body: some View {
        List {
            Section(AppL10n.string("settings.typingInput.schema.section", language: config.uiLanguage)) {
                Picker(
                    AppL10n.string("settings.typingInput.schema.picker", language: config.uiLanguage),
                    selection: $configuration.schema
                ) {
                    ForEach(TypingInputSchema.allCases) { schema in
                        Text(AppL10n.string(schema.labelKey, language: config.uiLanguage))
                            .tag(schema)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                ForEach(PinyinFuzzyPair.allCases) { pair in
                    Toggle(
                        pair.displayName,
                        isOn: Binding(
                            get: { configuration.fuzzyPairs.contains(pair) },
                            set: { enabled in
                                configuration.setFuzzyPair(pair, enabled: enabled)
                                deployUpdatedSchemas()
                            }
                        )
                    )
                }
            } header: {
                Text(AppL10n.string("settings.typingInput.fuzzy.section", language: config.uiLanguage))
            } footer: {
                Text(AppL10n.string("settings.typingInput.fuzzy.footer", language: config.uiLanguage))
            }

            Section(AppL10n.string("settings.typingInput.resources.section", language: config.uiLanguage)) {
                HStack {
                    Text(AppL10n.string("settings.typingInput.resources.status", language: config.uiLanguage))
                    Spacer()
                    if isDeploying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(statusText)
                            .foregroundStyle(
                                hasDeploymentError ? palette.danger : palette.textSecondary
                            )
                    }
                }

                Button(AppL10n.string("settings.typingInput.resources.redeploy", language: config.uiLanguage)) {
                    deployUpdatedSchemas()
                }
                .disabled(isDeploying)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(AppL10n.string("settings.typingInput.title", language: config.uiLanguage))
        .navigationBarTitleDisplayMode(.inline)
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
