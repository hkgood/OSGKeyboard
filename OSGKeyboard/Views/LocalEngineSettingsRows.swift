// LocalEngineSettingsRows.swift
// OSGKeyboard · Main App
//
// "Local engine" block for the settings card.
//
// v0.2.0:
// - The on-device ASR engine is fixed at iOS 26 `SpeechAnalyzer` +
//   `DictationTranscriber`. The previous picker (SpeechAnalyzer vs
//   Qwen3 CoreML) and the `ModelListActionButton` row are gone with
//   the Qwen3 backend — there is nothing for the user to download.
// - The "Cloud polish after ASR" toggle replaces that surface. When
//   enabled, the transcript produced by the local engine is routed
//   through the user's configured LLM (DeepSeek by default) before
//   insertion. When disabled, the local engine is pure on-device ASR.
// - The toggle warns the user that enabling it sends text to a cloud
//   API and gates on a non-empty Keychain — the Keychain-write UI
//   lives in `APISettingsCard` (cloud engine shares the same field).

import SwiftUI
import OSGKeyboardShared

// MARK: - Local models group (v0.2.0)

struct LocalModelsGroup: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        // v0.2.1 follow-up: the LocalEngineGroup now owns the
        // translation row so the local-engine Settings tab reads as
        // one cohesive card. The same surface chrome
        // (`palette.surface` + rounded border) the cloud branch uses
        // on its own card wraps the whole group so it sits flush with
        // the language tab above.
        VStack(spacing: 0) {
            speechRow
            Divider().background(palette.divider)
            cloudPolishRow
            if config.isTranslationRowVisible {
                Divider().background(palette.divider)
                TranslationPickerRow(config: config, isVisible: true)
            }
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    // MARK: Speech row

    /// Single-line summary that surfaces the only on-device ASR engine
    /// in v0.2.0 (iOS 26 `SpeechAnalyzer`) with a "built-in" badge so
    /// the user sees there is nothing to download.
    private var speechRow: some View {
        HStack(spacing: Spacing.xs) {
            Text("settings.localModels.speechRole")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: Spacing.xs)
            builtInBadge
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    // MARK: Cloud polish toggle

    /// Switch that turns on the post-ASR cloud-polish step. The toggle
    /// itself is always live (the user can flip it without having a
    /// key yet), but the polish call short-circuits with an Alert if
    /// the Keychain is empty when it fires.
    ///
    /// v0.2.1 follow-up: dropped the inline "uses DeepSeek" caption
    /// (the user already opted into cloud mode by switching engines,
    /// and the vendor name surfaces when they tap the row's helper
    /// text in onboarding / deep links). Title + switch is enough.
    private var cloudPolishRow: some View {
        Toggle(isOn: $config.localModeCloudPolishEnabled) {
            Text("settings.localModels.cloudPolish.title")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
        }
        .toggleStyle(.switch)
        .tint(palette.accent)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    // MARK: Helpers

    private var builtInBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("settings.localModels.builtIn")
                .font(TypeStyle.caption)
        }
        .foregroundStyle(palette.accent)
    }
}