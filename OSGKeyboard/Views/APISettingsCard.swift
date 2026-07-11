// APISettingsCard.swift
// OSGKeyboard · Main App
//
// Editable fields for the three OpenAI-compatible config values:
// Base URL, API Key, Model.

import SwiftUI
import OSGKeyboardShared

struct APISettingsCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    /// 嵌入合并卡片时为 `false`，由外层统一绘制圆角背景。
    var showsSurface: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            SettingsCredentialRow(
                title: AppL10n.string("api.key"),
                placeholder: "sk-…",
                text: $config.apiKey,
                isSecret: true,
                isMonospaced: true
            )
            rowDivider
            SettingsCredentialRow(
                title: AppL10n.string("api.baseUrl"),
                placeholder: LLMProvider.provider(id: config.providerId).defaultBaseURL,
                text: $config.baseURL,
                isMonospaced: true
            )
            rowDivider
            SettingsModelPickerRow(
                title: AppL10n.string("api.model"),
                placeholder: LLMProvider.provider(id: config.providerId).defaultModel,
                model: $config.model,
                fetchModels: fetchModels
            )
            .id(config.providerId)
            rowDivider
            thinkingRow
            rowDivider
            SettingsProviderToolsRow(validate: validateConnection)
        }
        .modifier(SettingsSurfaceCardModifier(enabled: showsSurface))
    }

    private var rowDivider: some View {
        Divider().background(palette.divider)
    }

    /// Two-line thinking toggle — opt-in for slower, higher-quality polish.
    private var thinkingRow: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(AppL10n.string("settings.provider.thinking"))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppL10n.string("settings.provider.thinkingSubtitle"))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $config.llmThinkingEnabled)
                .labelsHidden()
                .tint(palette.accent)
                .accessibilityLabel(AppL10n.string("settings.provider.thinking"))
        }
        .settingsListRow()
    }

    private func validateConnection() async throws {
        // Use on-screen config — not a fresh AppGroupStore — so a just-typed
        // key is visible even if Keychain write is still settling.
        let client = LLMClientFactory.make(
            providerId: config.providerId,
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model,
            thinkingEnabled: config.llmThinkingEnabled
        )
        _ = try await client.polish("ping", systemPrompt: "Reply with the single word PONG.")
    }

    private func fetchModels() async throws -> [String] {
        try await ProviderModelService.listLLMModels(
            providerId: config.providerId,
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            currentModel: config.model
        )
    }
}
