// ASRSettingsCard.swift
// OSGKeyboard · Main App
//
// Cloud ASR credentials — independent from the polish LLM card.

import SwiftUI
import OSGKeyboardShared
import OSGKeyboardHostSupport

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
            SettingsProviderToolsRow(
                providerIdentity: config.asrProviderId,
                endpointIdentity: config.asrBaseURL,
                credentialIdentity: config.asrApiKey,
                modelIdentity: config.asrModel,
                makeValidateRequest: makeValidateRequest
            )
        }
        .surfaceCard(enabled: showsSurface)
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
            providerIdentity: config.asrProviderId,
            endpointIdentity: config.asrBaseURL,
            credentialIdentity: config.asrApiKey,
            makeFetchModelsRequest: makeFetchModelsRequest
        )
        .id(config.asrProviderId)
    }

    private var volcengineRows: some View {
        Group {
            Toggle(isOn: volcengineAPIKeyModeBinding) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("settings.asr.volcengine.apiKeyMode.title")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                    Text("settings.asr.volcengine.apiKeyMode.subtitle")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(palette.accent)
            .settingsListRow()

            rowDivider

            if volcengineFields.usesAPIKeyAuth {
                SettingsCredentialRow(
                    title: AppL10n.string("settings.asr.volcengine.apiKey"),
                    placeholder: "API Key",
                    text: Binding(
                        get: { volcengineFields.apiKeyCredential },
                        set: { updateVolcengine(apiKeyCredential: $0) }
                    ),
                    isSecret: true,
                    isMonospaced: true
                )
            } else {
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
            }
        }
    }

    private var rowDivider: some View {
        Divider().background(palette.divider)
    }

    private var volcengineFields: VolcengineASRFields {
        VolcengineASRFields.parse(apiKey: config.asrApiKey)
    }

    private var volcengineAPIKeyModeBinding: Binding<Bool> {
        Binding(
            get: { volcengineFields.usesAPIKeyAuth },
            set: { updateVolcengine(authMode: $0 ? .apiKey : .appToken) }
        )
    }

    private func updateVolcengine(
        authMode: VolcengineASRAuthMode? = nil,
        appID: String? = nil,
        accessToken: String? = nil,
        apiKeyCredential: String? = nil
    ) {
        var fields = volcengineFields
        if let authMode { fields.authMode = authMode }
        if let appID { fields.appID = appID }
        if let accessToken { fields.accessToken = accessToken }
        if let apiKeyCredential { fields.apiKeyCredential = apiKeyCredential }
        // Keep store model aligned with the locked SAUC 2.0 resource.
        config.asrModel = VolcengineASRFields.fixedResourceID
        config.asrApiKey = fields.encodedAPIKey
    }

    @MainActor
    private func makeValidateRequest() -> ProviderToolRequest<Void> {
        let persisted = AppGroupStore()
        let store = LiveConfigurationStore(config: config, fallback: persisted)
        let providerID = config.asrProviderId
        return ProviderToolRequest(providerIdentity: providerID) {
            try await CloudASRConnectionCheck.validate(store: store)
        }
    }

    @MainActor
    private func makeFetchModelsRequest() -> ProviderToolRequest<[String]> {
        let providerID = config.asrProviderId
        let baseURL = config.asrBaseURL
        let apiKey = config.asrApiKey
        let currentModel = config.asrModel
        return ProviderToolRequest(providerIdentity: providerID) {
            try await ProviderModelService.listASRModels(
                providerId: providerID,
                baseURL: baseURL,
                apiKey: apiKey,
                currentModel: currentModel
            )
        }
    }
}
