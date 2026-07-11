// ASRSettingsCard.swift
// OSGKeyboard · Main App
//
// Cloud ASR credentials — independent from the polish LLM card.

import SwiftUI
import OSGKeyboardShared

struct ASRSettingsCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    /// 嵌入合并卡片时为 `false`，由外层统一绘制圆角背景。
    var showsSurface: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if config.asrProviderId == "volcengine" {
                volcengineRows
            } else {
                genericRows
            }
            rowDivider
            SettingsProviderToolsRow(validate: validateConnection)
        }
        .modifier(SettingsSurfaceCardModifier(enabled: showsSurface))
    }

    @ViewBuilder
    private var genericRows: some View {
        if CloudASRModelCatalog.showsASREndpointField(for: config.asrProviderId) {
            SettingsCredentialRow(
                title: AppL10n.string("api.baseUrl"),
                placeholder: LLMProvider.provider(id: config.asrProviderId).defaultBaseURL,
                text: $config.asrBaseURL,
                isMonospaced: true
            )
            rowDivider
        }

        SettingsCredentialRow(
            title: AppL10n.string("api.key"),
            placeholder: "sk-…",
            text: $config.asrApiKey,
            isSecret: true,
            isMonospaced: true
        )
        rowDivider
        SettingsModelPickerRow(
            title: AppL10n.string("settings.asr.model"),
            placeholder: CloudASRModelCatalog.defaultModel(for: config.asrProviderId),
            model: $config.asrModel,
            fetchModels: fetchModels
        )
        .id(config.asrProviderId)
    }

    private var volcengineRows: some View {
        Group {
            SettingsCredentialRow(
                title: AppL10n.string("settings.asr.volcengine.appId"),
                placeholder: "APP ID",
                text: Binding(
                    get: { volcengineFields.appID },
                    set: { updateVolcengine(appID: $0) }
                ),
                isSecret: true,
                isMonospaced: true
            )
            rowDivider
            SettingsCredentialRow(
                title: AppL10n.string("settings.asr.volcengine.accessToken"),
                placeholder: "Access Token",
                text: Binding(
                    get: { volcengineFields.accessToken },
                    set: { updateVolcengine(accessToken: $0) }
                ),
                isSecret: true,
                isMonospaced: true
            )
            rowDivider
            SettingsCredentialRow(
                title: AppL10n.string("settings.asr.volcengine.resourceId"),
                placeholder: CloudASRModelCatalog.defaultModel(for: "volcengine"),
                text: Binding(
                    get: { volcengineFields.resourceID },
                    set: { updateVolcengine(resourceID: $0) }
                ),
                isMonospaced: true,
                defaultValue: CloudASRModelCatalog.defaultModel(for: "volcengine")
            )
            rowDivider
            SettingsProviderRow(title: AppL10n.string("settings.provider.note")) {
                Text("settings.asr.volcengine.note")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rowDivider: some View {
        Divider().background(palette.divider)
    }

    private var volcengineFields: VolcengineASRFields {
        VolcengineASRFields.parse(
            apiKey: config.asrApiKey,
            resourceFallback: config.asrModel.isEmpty
                ? CloudASRModelCatalog.defaultModel(for: "volcengine")
                : config.asrModel
        )
    }

    private func updateVolcengine(appID: String? = nil, accessToken: String? = nil, resourceID: String? = nil) {
        var fields = volcengineFields
        if let appID { fields.appID = appID }
        if let accessToken { fields.accessToken = accessToken }
        if let resourceID {
            fields.resourceID = resourceID
            config.asrModel = resourceID
        }
        config.asrApiKey = fields.encodedAPIKey
    }

    private func validateConnection() async throws {
        let persisted = AppGroupStore()
        let live = LiveConfigurationStore(config: config, fallback: persisted)
        try await CloudASRConnectionCheck.validate(store: live)
    }

    private func fetchModels() async throws -> [String] {
        try await ProviderModelService.listASRModels(
            providerId: config.asrProviderId,
            baseURL: config.asrBaseURL,
            apiKey: config.asrApiKey,
            currentModel: config.asrModel
        )
    }
}
