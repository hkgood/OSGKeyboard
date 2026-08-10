// LocalEngineSettingsRows.swift
// OSGKeyboard · Main App
//
// "Local engine" block for the settings card.
//
// - On-device ASR is fixed at iOS 26 `SpeechAnalyzer` +
//   `DictationTranscriber` (nothing to download).
// - Post-ASR polish uses the LLM provider / API key configured in Settings.

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
#if DEBUG
            Divider().background(palette.divider)
            customLanguageModelDiagnosticRow
#endif
        }
        .surfaceCard()
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
        .settingsListRow()
    }

    // MARK: Polish row

    /// Local ASR still works without a key; polish requires the Settings LLM key.
    private var polishRow: some View {
        HStack(spacing: Spacing.xs) {
            Text("settings.localModels.polishRole")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.xs)
            if config.isPolishConfigured {
                engineBadge(
                    Text(LLMProvider.provider(id: config.providerId).name)
                )
            } else {
                Text("settings.localModels.polishNeedsKey")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.warning)
            }
        }
        .settingsListRow()
    }

    // MARK: Custom language model diagnostic row (DEBUG builds only)

#if DEBUG
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
        .settingsListRow()
    }
#endif

    // MARK: Helpers

    /// Accent badge naming the engine that backs each local-mode row
    /// (e.g. "Apple iOS Speech" for ASR).
    private func engineBadge(_ labelKey: LocalizedStringKey) -> some View {
        engineBadge(Text(labelKey))
    }

    private func engineBadge(_ label: Text) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            label
                .font(TypeStyle.caption)
        }
        .foregroundStyle(palette.accent)
    }
}
