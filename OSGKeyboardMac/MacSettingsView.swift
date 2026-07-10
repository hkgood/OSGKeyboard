// MacSettingsView.swift
// OSGKeyboard · Mac
//
// Settings uses native grouped `Form` for correct control layout (Picker /
// Toggle / LabeledContent). Title and Form share the same plain
// `pageHorizontalInset` padding (Form scroll margins are zeroed first) so
// card chrome lines up with the page title.

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
    @State private var showProviderPicker = false
    @State private var showAsrProviderPicker = false

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

                Form {
                    generalSection
                    recognitionSection
                    polishProviderSection
                    if viewModel.config.engineMode == "cloud" {
                        asrProviderSection
                            .transition(.opacity)
                    }
                    if viewModel.config.engineMode == "local" {
                        MacLocalASRModelSettingsView(viewModel: viewModel)
                            .transition(.opacity)
                    }
                    inputSection
                    legalSection
                }
                .formStyle(.grouped)
                // Zero Form's own scroll margins, then inset via padding so the
                // section cards line up with MacPageHeader (contentMargins alone
                // does not match plain padding on macOS).
                //
                // grouped Form adds its own built-in section inset on top of our
                // padding, so cards sat ~`groupedFormSectionInset` wider than the
                // History page. Subtract that inset here so the card OUTER edge
                // lands on `pageHorizontalInset` (40pt), matching History and the
                // page title's left edge.
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .padding(.horizontal, MacMetrics.pageHorizontalInset - MacMetrics.groupedFormSectionInset)
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
        Section(MacL10n.string("mac.settings.general", language: lang)) {
            Picker(MacL10n.string("mac.settings.appearance", language: lang), selection: $appearanceRaw) {
                ForEach(MacAppearancePreference.allCases) { pref in
                    Text(MacL10n.string(pref.labelKey, language: lang)).tag(pref.rawValue)
                }
            }

            Picker(MacL10n.string("mac.settings.interfaceLanguage", language: lang), selection: interfaceLanguageBinding) {
                ForEach(AppUILanguage.allCases, id: \.self) { language in
                    Text(MacL10n.string(language.labelKey, language: lang)).tag(language.rawValue)
                }
            }

            Picker(MacL10n.string("mac.settings.recognitionLanguage", language: lang), selection: recognitionLanguageBinding) {
                ForEach(recognitionLocales, id: \.id) { locale in
                    Text(localeLabel(locale)).tag(locale.id)
                }
            }

            MacSettingsICloudSyncRow(defaults: viewModel.defaults, language: lang)
            MacDictionaryICloudSyncRow(defaults: viewModel.defaults, language: lang)
        }
    }

    // MARK: - Polish LLM

    private var polishProviderSection: some View {
        Section(MacL10n.string("mac.settings.polishProvider", language: lang)) {
            providerPickerRow(
                title: MacL10n.string("mac.settings.service", language: lang),
                provider: currentPolishProvider,
                isPresented: $showProviderPicker
            ) {
                providerPickerList(
                    providers: viewModel.polishSelectableProviders,
                    selectedId: viewModel.config.providerId
                ) { provider in
                    viewModel.selectProvider(provider)
                    showProviderPicker = false
                }
            }

            LabeledContent {
                SecureField(text: $viewModel.config.apiKey, prompt: Text(verbatim: "sk-…")) {
                    Text(MacL10n.string("mac.settings.apiKey", language: lang))
                }
                .labelsHidden()
                .macFieldStyle()
                .frame(maxWidth: MacMetrics.controlWidth)
            } label: {
                Text(MacL10n.string("mac.settings.apiKey", language: lang))
            }

            LabeledContent {
                TextField(text: $viewModel.config.baseURL, prompt: Text(verbatim: "")) {
                    Text(MacL10n.string("mac.settings.baseURL", language: lang))
                }
                .labelsHidden()
                .macFieldStyle()
                .frame(maxWidth: MacMetrics.controlWidth)
            } label: {
                Text(MacL10n.string("mac.settings.baseURL", language: lang))
            }

            LabeledContent {
                TextField(text: $viewModel.config.model, prompt: Text(verbatim: "")) {
                    Text(MacL10n.string("mac.settings.model", language: lang))
                }
                .labelsHidden()
                .macFieldStyle()
                .frame(maxWidth: MacMetrics.controlWidth)
            } label: {
                Text(MacL10n.string("mac.settings.model", language: lang))
            }
        }
    }

    // MARK: - Cloud ASR

    private var asrProviderSection: some View {
        Section(MacL10n.string("mac.settings.asrProvider", language: lang)) {
            providerPickerRow(
                title: MacL10n.string("mac.settings.asrService", language: lang),
                provider: currentAsrProvider,
                isPresented: $showAsrProviderPicker
            ) {
                providerPickerList(
                    providers: viewModel.asrSelectableProviders,
                    selectedId: viewModel.config.asrProviderId
                ) { provider in
                    viewModel.selectAsrProvider(provider)
                    showAsrProviderPicker = false
                }
            }

            LabeledContent {
                SecureField(text: $viewModel.config.asrApiKey, prompt: Text(verbatim: "sk-…")) {
                    Text(MacL10n.string("mac.settings.apiKey", language: lang))
                }
                .labelsHidden()
                .macFieldStyle()
                .frame(maxWidth: MacMetrics.controlWidth)
            } label: {
                Text(MacL10n.string("mac.settings.asrApiKey", language: lang))
            }

            if CloudASRModelCatalog.strategy(for: viewModel.config.asrProviderId) == .prompt {
                LabeledContent {
                    TextField(text: $viewModel.config.asrBaseURL, prompt: Text(verbatim: "")) {
                        Text(MacL10n.string("mac.settings.baseURL", language: lang))
                    }
                    .labelsHidden()
                    .macFieldStyle()
                    .frame(maxWidth: MacMetrics.controlWidth)
                } label: {
                    Text(MacL10n.string("mac.settings.baseURL", language: lang))
                }
            }

            LabeledContent {
                TextField(text: $viewModel.config.asrModel, prompt: Text(verbatim: "")) {
                    Text(MacL10n.string("mac.settings.asrModel", language: lang))
                }
                .labelsHidden()
                .macFieldStyle()
                .frame(maxWidth: MacMetrics.controlWidth)
            } label: {
                Text(MacL10n.string("mac.settings.asrModel", language: lang))
            }
        }
    }

    private func providerPickerRow<Content: View>(
        title: String,
        provider: LLMProvider,
        isPresented: Binding<Bool>,
        @ViewBuilder picker: @escaping () -> Content
    ) -> some View {
        LabeledContent(title) {
            Button {
                isPresented.wrappedValue = true
            } label: {
                HStack(spacing: 6) {
                    providerLogo(provider.id)
                    Text(provider.name)
                        .foregroundStyle(palette.textPrimary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: isPresented, arrowEdge: .bottom, content: picker)
        }
    }

    // MARK: - Recognition method

    private var recognitionSection: some View {
        Section(MacL10n.string("mac.settings.recognition", language: lang)) {
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

    // MARK: - Hotkey / paste

    private var inputSection: some View {
        Section(MacL10n.string("mac.settings.input", language: lang)) {
            Toggle(isOn: hotkeyBinding) {
                rowLabel(
                    MacL10n.string("mac.settings.hotkey", language: lang),
                    subtitle: MacL10n.string("mac.settings.hotkeyDesc", language: lang)
                )
            }

            Picker(selection: hotkeyTriggerBinding) {
                ForEach(MacHotkeyTrigger.allCases) { trigger in
                    Text(MacL10n.string(trigger.labelKey, language: lang))
                        .tag(trigger.rawValue)
                }
            } label: {
                rowLabel(
                    MacL10n.string("mac.settings.hotkeyTrigger", language: lang),
                    subtitle: MacL10n.string("mac.settings.hotkeyTriggerDesc", language: lang)
                )
            }
            .disabled(!viewModel.hotkeyEnabled)

            Toggle(isOn: autoPasteBinding) {
                rowLabel(
                    MacL10n.string("mac.settings.autoPaste", language: lang),
                    subtitle: MacL10n.string("mac.settings.autoPasteDesc", language: lang)
                )
            }

            LabeledContent {
                HStack(spacing: Spacing.sm) {
                    Label(
                        accessibilityTrusted ? accessibilityStatusGranted : accessibilityStatusNeeded,
                        systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .font(TypeStyle.caption)
                    .foregroundStyle(accessibilityTrusted ? palette.accent : palette.warning)
                    .contentTransition(.opacity)
                    .animation(Motion.quick, value: accessibilityTrusted)

                    Button(MacL10n.string("mac.settings.openAccessibility", language: lang)) {
                        openAccessibilitySettings()
                    }
                }
            } label: {
                rowLabel(
                    MacL10n.string("mac.settings.accessibility", language: lang),
                    subtitle: MacL10n.string("mac.settings.accessibilityDesc", language: lang)
                )
            }
        }
    }

    // MARK: - Legal

    private var legalSection: some View {
        Section(MacL10n.string("mac.settings.about", language: lang)) {
            NavigationLink {
                MacPrivacyPolicyView(uiLanguage: lang)
            } label: {
                Text(MacL10n.string("mac.settings.privacyPolicy", language: lang))
            }

            NavigationLink {
                MacOpenSourceLicensesView(uiLanguage: lang)
            } label: {
                Text(MacL10n.string("mac.settings.thirdPartyLicenses", language: lang))
            }

            Button(MacL10n.string("mac.settings.restartOnboarding", language: lang)) {
                hasCompletedMacOnboarding = false
            }
        }
    }

    // MARK: - Row helpers

    private func rowLabel(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

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

    private func providerPickerList(
        providers: [LLMProvider],
        selectedId: String,
        onSelect: @escaping (LLMProvider) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(providers) { provider in
                Button {
                    onSelect(provider)
                } label: {
                    HStack(spacing: Spacing.sm) {
                        providerLogo(provider.id)
                        Text(provider.name)
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: Spacing.md)
                        if provider.id == selectedId {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 260)
    }

    /// Brand mark tinted to the current label colour (black on light / white
    /// on dark). Template rendering + an explicit frame make the vector assets
    /// resolve at a text-matched size inside the pop-up menu — without a size
    /// hint they collapse to zero and disappear.
    @ViewBuilder
    private func providerLogo(_ providerId: String) -> some View {
        if let asset = ProviderLogo.assetName(for: providerId) {
            Image(asset)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private func providerLabel(_ provider: LLMProvider) -> some View {
        Label {
            Text(provider.name)
        } icon: {
            providerLogo(provider.id)
        }
    }

    // MARK: - Bindings

    private var interfaceLanguageBinding: Binding<String> {
        Binding(
            get: { viewModel.config.uiLanguage.rawValue },
            set: { viewModel.config.uiLanguage = AppUILanguage(rawValue: $0) ?? .auto }
        )
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { viewModel.config.providerId },
            set: { newId in
                if let provider = viewModel.selectableProviders.first(where: { $0.id == newId }) {
                    viewModel.selectProvider(provider)
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

    private var hotkeyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hotkeyEnabled },
            set: { viewModel.setHotkeyEnabled($0) }
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
