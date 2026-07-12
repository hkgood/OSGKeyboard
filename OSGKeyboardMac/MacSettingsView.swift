// MacSettingsView.swift
// OSGKeyboard · Mac
//
// Settings uses native grouped `Form`. LLM / ASR provider blocks use a merged
// `MacSettingsProviderCard` with responsive rows and theme-aware controls.

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct MacSettingsView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Environment(\.themePalette) private var palette

    @AppStorage(MacAppearancePreference.storageKey)
    private var appearanceRaw = MacAppearancePreference.system.rawValue
    @AppStorage(MacOnboardingState.storageKey)
    private var hasCompletedMacOnboarding = true
    @State private var accessibilityTrusted = MacTextInsertionService.isAccessibilityTrusted

    private var lang: AppUILanguage { viewModel.config.uiLanguage }
    private let recognitionLocales: [(id: String, key: String, fallback: String)] = [
        ("auto", "locale.auto", "Auto"),
        ("zh-Hans", "locale.zh-Hans", "Chinese (Simplified)"),
        ("zh-Hant", "locale.zh-Hant", "Chinese (Traditional)"),
        ("en-US", "locale.en-US", "English (US)"),
        ("ja-JP", "locale.ja-JP", "Japanese"),
        ("ko-KR", "locale.ko-KR", "Korean")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MacPageHeader(
                    title: MacL10n.string("mac.section.settings", language: lang),
                    subtitle: MacL10n.string("mac.page.settings.subtitle", language: lang)
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                        supportSection
                        generalSection
                        recognitionSection
                        if viewModel.config.engineMode == "cloud" {
                            asrProviderSection
                                .transition(.opacity)
                        }
                        if viewModel.config.engineMode == "local" {
                            MacLocalASRModelSettingsView(viewModel: viewModel)
                                .transition(.opacity)
                        }
                        polishProviderSection
                        inputSection
                        legalSection
                    }
                    .padding(.horizontal, MacMetrics.pageHorizontalInset)
                    .padding(.bottom, Spacing.md)
                }
                .tint(palette.accent)
                .scrollContentBackground(.hidden)
                .background(palette.background)
            }
            .background(palette.background)
        }
        .onAppear { refreshAccessibilityState() }
    }

    // MARK: - General

    private var generalSection: some View {
        MacSettingsSection(title: MacL10n.string("mac.settings.general", language: lang)) {
            VStack(spacing: MacMetrics.settingsRowGap) {
                MacProviderSettingRow(title: MacL10n.string("mac.settings.appearance", language: lang)) {
                    MacInlinePicker(
                        selection: $appearanceRaw,
                        options: MacAppearancePreference.allCases.map {
                            MacInlinePickerOption(value: $0.rawValue, label: MacL10n.string($0.labelKey, language: lang))
                        },
                        fillsWidth: true
                    )
                }

                MacProviderSettingRow(title: MacL10n.string("mac.settings.interfaceLanguage", language: lang)) {
                    MacInlinePicker(
                        selection: interfaceLanguageBinding,
                        options: AppUILanguage.allCases.map {
                            MacInlinePickerOption(value: $0.rawValue, label: MacL10n.string($0.labelKey, language: lang))
                        },
                        fillsWidth: true
                    )
                }

                MacProviderSettingRow(title: MacL10n.string("mac.settings.recognitionLanguage", language: lang)) {
                    MacInlinePicker(
                        selection: recognitionLanguageBinding,
                        options: recognitionLocales.map {
                            MacInlinePickerOption(value: $0.id, label: localeLabel($0))
                        },
                        fillsWidth: true
                    )
                }

                MacSettingsICloudSyncRow(defaults: viewModel.defaults, language: lang)
            }
        }
    }

    // MARK: - Polish LLM

    private var polishProviderSection: some View {
        MacSettingsSection(title: MacL10n.string("mac.settings.polishProvider", language: lang)) {
            MacSettingsProviderCard {
                MacProviderPickerRow(
                    title: MacL10n.string("mac.settings.service", language: lang),
                    providers: viewModel.polishSelectableProviders,
                    selection: polishProviderBinding
                )
                MacCredentialField(
                    title: MacL10n.string("mac.settings.apiKey", language: lang),
                    placeholder: "sk-…",
                    text: $viewModel.config.apiKey,
                    isSecret: true
                )
                MacCredentialField(
                    title: MacL10n.string("mac.settings.baseURL", language: lang),
                    placeholder: currentPolishProvider.defaultBaseURL,
                    text: $viewModel.config.baseURL
                )
                MacProviderModelRow(
                    title: MacL10n.string("mac.settings.model", language: lang),
                    placeholder: currentPolishProvider.defaultModel,
                    model: $viewModel.config.model,
                    apiKey: viewModel.config.apiKey,
                    fetchModels: fetchMacLLMModels,
                    language: lang
                )
                .id(viewModel.config.providerId)
                MacProviderThinkingRow(
                    title: MacL10n.string("mac.settings.thinking", language: lang),
                    subtitle: MacL10n.string("mac.settings.thinkingSubtitle", language: lang),
                    isOn: $viewModel.config.llmThinkingEnabled
                )
                MacProviderToolsRow(
                    title: MacL10n.string("mac.settings.connectionCheck", language: lang),
                    validate: validateMacLLM,
                    language: lang
                )
            }
        }
    }

    // MARK: - Cloud ASR

    private var asrProviderSection: some View {
        MacSettingsSection(title: MacL10n.string("mac.settings.asrProvider", language: lang)) {
            MacSettingsProviderCard {
                MacProviderPickerRow(
                    title: MacL10n.string("mac.settings.asrService", language: lang),
                    providers: viewModel.asrSelectableProviders,
                    selection: asrProviderBinding
                )
                if viewModel.config.asrProviderId == "volcengine" {
                    volcengineAsrRows
                } else {
                    genericAsrRows
                }
                MacProviderToolsRow(
                    title: MacL10n.string("mac.settings.connectionCheck", language: lang),
                    validate: validateMacASR,
                    language: lang
                )
            }
        }
    }

    @ViewBuilder
    private var volcengineAsrRows: some View {
        MacCredentialField(
            title: MacL10n.string("mac.settings.volcengineAppId", language: lang),
            placeholder: "APP ID",
            text: Binding(
                get: { macVolcengineFields.appID },
                set: { updateMacVolcengine(appID: $0) }
            ),
            isSecret: true
        )
        MacCredentialField(
            title: MacL10n.string("mac.settings.volcengineAccessToken", language: lang),
            placeholder: "Access Token",
            text: Binding(
                get: { macVolcengineFields.accessToken },
                set: { updateMacVolcengine(accessToken: $0) }
            ),
            isSecret: true
        )
        MacCredentialField(
            title: MacL10n.string("mac.settings.volcengineResourceId", language: lang),
            placeholder: CloudASRModelCatalog.defaultModel(for: "volcengine"),
            text: Binding(
                get: { macVolcengineFields.resourceID },
                set: { updateMacVolcengine(resourceID: $0) }
            ),
            defaultValue: CloudASRModelCatalog.defaultModel(for: "volcengine")
        )
        MacProviderNoteRow(text: MacL10n.string("mac.settings.volcengineNote", language: lang))
    }

    @ViewBuilder
    private var genericAsrRows: some View {
        if CloudASRModelCatalog.showsASREndpointField(for: viewModel.config.asrProviderId) {
            MacCredentialField(
                title: MacL10n.string("mac.settings.baseURL", language: lang),
                placeholder: currentAsrProvider.defaultBaseURL,
                text: $viewModel.config.asrBaseURL
            )
        }

        MacCredentialField(
            title: MacL10n.string("mac.settings.asrApiKey", language: lang),
            placeholder: "sk-…",
            text: $viewModel.config.asrApiKey,
            isSecret: true
        )
        MacProviderModelRow(
            title: MacL10n.string("mac.settings.asrModel", language: lang),
            placeholder: CloudASRModelCatalog.defaultModel(for: viewModel.config.asrProviderId),
            model: $viewModel.config.asrModel,
            apiKey: viewModel.config.asrApiKey,
            fetchModels: fetchMacASRModels,
            language: lang
        )
        .id(viewModel.config.asrProviderId)
    }

    // MARK: - Recognition method

    private var recognitionSection: some View {
        MacSettingsSection(title: MacL10n.string("mac.settings.recognition", language: lang)) {
            VStack(spacing: MacMetrics.settingsRowGap) {
                methodRow(
                title: MacL10n.string("mac.settings.cloudEngine", language: lang),
                subtitle: MacL10n.string("mac.settings.cloudEngineDesc", language: lang),
                systemImage: "cloud",
                selected: viewModel.config.engineMode == "cloud"
            ) { withAnimation(Motion.soft) { viewModel.setEngineMode("cloud") } }
                methodRow(
                title: MacL10n.string("mac.settings.localEngine", language: lang),
                subtitle: MacL10n.string("mac.settings.localEngineDesc", language: lang),
                systemImage: "cpu",
                selected: viewModel.config.engineMode == "local"
            ) { withAnimation(Motion.soft) { viewModel.setEngineMode("local") } }
            }
        }
    }

    // MARK: - Hotkey / paste

    private var inputSection: some View {
        MacSettingsSection(title: MacL10n.string("mac.settings.input", language: lang)) {
            VStack(spacing: MacMetrics.settingsRowGap) {
                MacProviderSettingRow(title: MacL10n.string("mac.settings.hotkeyTrigger", language: lang)) {
                    MacInlinePicker(
                        selection: hotkeyTriggerBinding,
                        options: MacHotkeyTrigger.allCases.map {
                            MacInlinePickerOption(value: $0.rawValue, label: MacL10n.string($0.labelKey, language: lang))
                        },
                        fillsWidth: true
                    )
                }
                MacProviderSettingRow(
                    title: MacL10n.string("mac.settings.autoPaste", language: lang),
                    verticalAlignment: .center
                ) {
                    Toggle("", isOn: autoPasteBinding)
                        .labelsHidden()
                        .toggleStyle(MacToggleStyle())
                }
                MacProviderSettingRow(
                    title: MacL10n.string("mac.settings.accessibility", language: lang),
                    verticalAlignment: .center
                ) {
                    HStack(spacing: Spacing.sm) {
                        MacSettingsToolButton(title: MacL10n.string("mac.settings.openAccessibility", language: lang)) {
                            openAccessibilitySettings()
                        }

                        Label(
                            accessibilityTrusted ? accessibilityStatusGranted : accessibilityStatusNeeded,
                            systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .font(TypeStyle.caption)
                        .foregroundStyle(accessibilityTrusted ? palette.accent : palette.warning)
                        .contentTransition(.opacity)
                        .animation(Motion.quick, value: accessibilityTrusted)
                    }
                }
            }
        }
    }

    // MARK: - Support developer

    private var supportSection: some View {
        MacSettingsSection(
            title: MacL10n.string("tip.title", language: lang),
            footer: MacL10n.string("tip.consumableNotice", language: lang)
        ) {
            MacSupportDeveloperTipRows(language: lang)
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        MacSettingsSection(title: MacL10n.string("mac.settings.about", language: lang)) {
            VStack(spacing: MacMetrics.settingsRowGap) {
                NavigationLink {
                    MacPrivacyPolicyView(uiLanguage: lang)
                } label: {
                    MacFormLinkRow(title: MacL10n.string("mac.settings.privacyPolicy", language: lang))
                }
                .buttonStyle(.plain)
                NavigationLink {
                    MacOpenSourceLicensesView(uiLanguage: lang)
                } label: {
                    MacFormLinkRow(title: MacL10n.string("mac.settings.thirdPartyLicenses", language: lang))
                }
                .buttonStyle(.plain)
                Button(MacL10n.string("mac.settings.restartOnboarding", language: lang)) {
                    hasCompletedMacOnboarding = false
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: MacMetrics.settingsRowMinHeight, alignment: .leading)
                .padding(.horizontal, MacMetrics.settingsCardInset)
            }
        }
    }

    // MARK: - Row helpers

    private func methodRow(
        title: String,
        subtitle: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selected ? palette.accent : palette.textTertiary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? palette.accent : palette.textTertiary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(minHeight: MacMetrics.settingsRowMinHeight)
            .padding(.horizontal, MacMetrics.settingsCardInset)
            .animation(Motion.quick, value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var currentPolishProvider: LLMProvider {
        viewModel.polishSelectableProviders.first { $0.id == viewModel.config.providerId }
            ?? viewModel.polishSelectableProviders.first
            ?? LLMProvider.presets[0]
    }

    private var currentAsrProvider: LLMProvider {
        viewModel.asrSelectableProviders.first { $0.id == viewModel.config.asrProviderId }
            ?? viewModel.asrSelectableProviders.first
            ?? LLMProvider.presets[0]
    }

    private var macVolcengineFields: VolcengineASRFields {
        VolcengineASRFields.parse(
            apiKey: viewModel.config.asrApiKey,
            resourceFallback: viewModel.config.asrModel.isEmpty
                ? CloudASRModelCatalog.defaultModel(for: "volcengine")
                : viewModel.config.asrModel
        )
    }

    private func updateMacVolcengine(appID: String? = nil, accessToken: String? = nil, resourceID: String? = nil) {
        var fields = macVolcengineFields
        if let appID { fields.appID = appID }
        if let accessToken { fields.accessToken = accessToken }
        if let resourceID {
            fields.resourceID = resourceID
            viewModel.config.asrModel = resourceID
        }
        viewModel.config.asrApiKey = fields.encodedAPIKey
    }

    private func validateMacLLM() async throws {
        let client = LLMClientFactory.make(
            providerId: viewModel.config.providerId,
            baseURL: viewModel.config.baseURL,
            apiKey: viewModel.config.apiKey,
            model: viewModel.config.model,
            thinkingEnabled: viewModel.config.llmThinkingEnabled
        )
        _ = try await client.polish("ping", systemPrompt: "Reply with the single word PONG.")
    }

    private func fetchMacLLMModels() async throws -> [String] {
        try await ProviderModelService.listLLMModels(
            providerId: viewModel.config.providerId,
            baseURL: viewModel.config.baseURL,
            apiKey: viewModel.config.apiKey,
            currentModel: viewModel.config.model
        )
    }

    private func validateMacASR() async throws {
        let persisted = AppGroupStore(defaults: viewModel.defaults)
        let store = LiveConfigurationStore(config: viewModel.config, fallback: persisted)
        try await CloudASRConnectionCheck.validate(store: store)
    }

    private func fetchMacASRModels() async throws -> [String] {
        try await ProviderModelService.listASRModels(
            providerId: viewModel.config.asrProviderId,
            baseURL: viewModel.config.asrBaseURL,
            apiKey: viewModel.config.asrApiKey,
            currentModel: viewModel.config.asrModel
        )
    }

    // MARK: - Bindings

    private var interfaceLanguageBinding: Binding<String> {
        Binding(
            get: { viewModel.config.uiLanguage.rawValue },
            set: { viewModel.config.uiLanguage = AppUILanguage(rawValue: $0) ?? .auto }
        )
    }

    private var polishProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.config.providerId },
            set: { newId in
                if let provider = viewModel.polishSelectableProviders.first(where: { $0.id == newId }) {
                    viewModel.selectProvider(provider)
                }
            }
        )
    }

    private var asrProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.config.asrProviderId },
            set: { newId in
                if let provider = viewModel.asrSelectableProviders.first(where: { $0.id == newId }) {
                    viewModel.selectAsrProvider(provider)
                }
            }
        )
    }

    private var recognitionLanguageBinding: Binding<String> {
        Binding(
            get: {
                let current = viewModel.config.localeId
                return current.isEmpty ? "auto" : current
            },
            set: { newValue in
                viewModel.config.localeId = newValue == "auto" ? "" : newValue
            }
        )
    }

    private var hotkeyTriggerBinding: Binding<String> {
        Binding(
            get: { viewModel.hotkeyTrigger.rawValue },
            set: { viewModel.setHotkeyTrigger(MacHotkeyTrigger(rawValue: $0) ?? .rightOption) }
        )
    }

    private var autoPasteBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoPasteEnabled },
            set: { viewModel.setAutoPasteEnabled($0) }
        )
    }

    // MARK: - AppKit actions (macOS only)

    private func openAccessibilitySettings() {
        #if os(macOS)
        _ = MacTextInsertionService.requestAccessibilityIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshAccessibilityState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshAccessibilityState()
        }
        #endif
    }

    private func refreshAccessibilityState() {
        accessibilityTrusted = MacTextInsertionService.isAccessibilityTrusted
    }

    private func localeLabel(_ locale: (id: String, key: String, fallback: String)) -> String {
        let resolved = AppUILanguage.localizedString(
            locale.key,
            tableName: nil,
            bundle: .main,
            language: lang
        )
        return resolved == locale.key ? locale.fallback : resolved
    }

    private var accessibilityStatusGranted: String {
        lang.resolvedLanguageCode().hasPrefix("zh") ? "已授权" : "Granted"
    }

    private var accessibilityStatusNeeded: String {
        lang.resolvedLanguageCode().hasPrefix("zh") ? "未授权" : "Needed"
    }
}
