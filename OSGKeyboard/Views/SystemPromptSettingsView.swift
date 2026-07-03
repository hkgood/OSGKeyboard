// SystemPromptSettingsView.swift
// OSGKeyboard · Main App
//
// Cloud-engine system prompt editor. Reached from Settings when the
// user picks the cloud recognition path.

import SwiftUI
import OSGKeyboardShared

struct SystemPromptSettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("settings.systemPrompt.hint")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if config.isCustomPolishScenario {
                    Text("settings.polishScenario.customHint")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextEditor(text: $config.systemPrompt)
                    .font(TypeStyle.mono)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 320)
                    .padding(Spacing.sm)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.systemPrompt.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("common.reset") {
                    config.systemPrompt = config.defaultSystemPrompt
                }
                .font(TypeStyle.body)
                .foregroundStyle(palette.accent)
            }
        }
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
