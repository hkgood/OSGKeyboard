// LocalEngineSettingsRows.swift
// OSGKeyboard · Main App
//
// "Local engine" block for the settings card.
//
// v0.2.0:
// - On-device ASR is fixed at iOS 26 `SpeechAnalyzer` +
//   `DictationTranscriber` (nothing to download).
// - Post-ASR polish is always on via the built-in DeepSeek path
//   (`PreconfiguredKeys.local.swift`, gitignored). The user never
//   pastes a key for local mode.

import SwiftUI
import OSGKeyboardShared

// MARK: - Local models group (v0.2.0)

struct LocalModelsGroup: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        VStack(spacing: 0) {
            speechRow
            Divider().background(palette.divider)
            polishRow
            Divider().background(palette.divider)
            customLanguageModelDiagnosticRow
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    // MARK: Speech row

    private var speechRow: some View {
        HStack(spacing: Spacing.xs) {
            Text("settings.localModels.speechRole")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.xs)
            engineBadge("settings.localModels.speechEngine")
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    // MARK: Polish row

    /// Built-in post-ASR polish for the local engine. No API key UI —
    /// the vendor key is supplied at build time only.
    private var polishRow: some View {
        HStack(spacing: Spacing.xs) {
            Text("settings.localModels.polishRole")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.xs)
            engineBadge("settings.localModels.polishEngine")
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    // MARK: Custom language model diagnostic row

    private var customLanguageModelDiagnosticRow: some View {
        Toggle(isOn: $config.localASRCustomLanguageModelEnabled) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("settings.localModels.customLM.title")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Text("settings.localModels.customLM.subtitle")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .tint(palette.accent)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    // MARK: Helpers

    /// Accent badge naming the engine that backs each local-mode row
    /// (e.g. "Apple iOS Speech" for ASR, "OSGKeyboard 内置" for polish).
    private func engineBadge(_ labelKey: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(labelKey)
                .font(TypeStyle.caption)
        }
        .foregroundStyle(palette.accent)
    }
}
