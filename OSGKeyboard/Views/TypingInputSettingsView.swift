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
    @State private var showClearHabitsConfirmation = false

    private var isDeploying: Bool { deployment.isDeploying }

    var body: some View {
        List {
            Section {
                Picker(
                    selection: $configuration.schema
                ) {
                    ForEach(TypingInputSchema.allCases) { schema in
                        Text(AppL10n.string(schema.labelKey, language: config.uiLanguage))
                            .font(TypeStyle.body)
                            .tag(schema)
                    }
                } label: {
                    Text(AppL10n.string("settings.typingInput.schema.picker", language: config.uiLanguage))
                        .font(TypeStyle.body)
                }
                .pickerStyle(.inline)
            } header: {
                Text(AppL10n.string("settings.typingInput.schema.section", language: config.uiLanguage))
                    .font(TypeStyle.caption2)
            }

            Section {
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
                }
            } header: {
                Text(AppL10n.string("settings.typingInput.fuzzy.section", language: config.uiLanguage))
                    .font(TypeStyle.caption2)
            } footer: {
                Text(AppL10n.string("settings.typingInput.fuzzy.footer", language: config.uiLanguage))
                    .font(TypeStyle.caption2)
            }

            Section {
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

                Button(AppL10n.string("settings.typingInput.resources.redeploy", language: config.uiLanguage)) {
                    deployUpdatedSchemas()
                }
                .font(TypeStyle.body)
                .disabled(isDeploying)
            } header: {
                Text(AppL10n.string("settings.typingInput.resources.section", language: config.uiLanguage))
                    .font(TypeStyle.caption2)
            }

            Section {
                Button(AppL10n.string("settings.typingInput.habits.clear", language: config.uiLanguage)) {
                    showClearHabitsConfirmation = true
                }
                .font(TypeStyle.body)
                .disabled(isDeploying)
                .foregroundStyle(palette.danger)
            } footer: {
                Text(AppL10n.string("settings.typingInput.habits.footer", language: config.uiLanguage))
                    .font(TypeStyle.caption2)
            }
        }
        .listSectionSpacing(CardLayoutMetrics.sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(AppL10n.string("settings.typingInput.title", language: config.uiLanguage))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            AppL10n.string("settings.typingInput.habits.clear.title", language: config.uiLanguage),
            isPresented: $showClearHabitsConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                AppL10n.string("settings.typingInput.habits.clear.confirm", language: config.uiLanguage),
                role: .destructive
            ) {
                deployment.clearTypingHabits()
            }
            Button(AppL10n.string("common.cancel", language: config.uiLanguage), role: .cancel) {}
        } message: {
            Text(AppL10n.string("settings.typingInput.habits.clear.message", language: config.uiLanguage))
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
