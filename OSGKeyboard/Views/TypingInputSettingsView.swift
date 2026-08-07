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

    @State private var isDeploying = false
    @State private var deploymentError: String?

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
                                deploymentError == nil ? palette.textSecondary : palette.danger
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

    private var statusText: String {
        if let deploymentError { return deploymentError }
        return AppL10n.string(
            RimeResourceInstaller.isReady
                ? "settings.typingInput.resources.ready"
                : "settings.typingInput.resources.pending",
            language: config.uiLanguage
        )
    }

    private func deployUpdatedSchemas() {
        guard !isDeploying else { return }
        let snapshot = configuration.snapshot
        isDeploying = true
        deploymentError = nil
        Task {
            do {
                try await RimeResourceInstaller.shared.installIfNeeded(
                    configuration: snapshot,
                    force: true
                )
            } catch {
                deploymentError = error.localizedDescription
            }
            isDeploying = false
        }
    }
}
