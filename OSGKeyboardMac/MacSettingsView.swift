// MacSettingsView.swift
// OSGKeyboard · Mac
//
// Settings built on the native grouped `Form` — the same container macOS
// System Settings uses. This gives system-accurate cards, dividers, insets
// and right-aligned controls for free, on both light and dark.

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
            Form {
                generalSection
                recognitionSection
                if viewModel.config.engineMode == "cloud" {
                    providerSection
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
            .tint(palette.accent)
            .scrollContentBackground(.hidden)
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

    // MARK: - Cloud provider

    private var providerSection: some View {
        Section(MacL10n.string("mac.settings.cloudProvider", language: lang)) {
            LabeledContent(MacL10n.string("mac.settings.service", language: lang)) {
                Button {
                    showProviderPicker = true
                } label: {
                    HStack(spacing: 6) {
                        providerLogo(currentProvider.id)
                        Text(currentProvider.name)
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showProviderPicker, arrowEdge: .bottom) {
                    providerPickerList
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

    private var currentProvider: LLMProvider {
        viewModel.selectableProviders.first { $0.id == viewModel.config.providerId }
            ?? viewModel.selectableProviders.first
            ?? LLMProvider.presets[0]
    }

    /// Custom dropdown list shown in a popover. SwiftUI's `Menu` label / items
    /// silently drop bundled (non-SF-Symbol) images on macOS, so we render the
    /// brand marks in a plain view stack instead.
    private var providerPickerList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.selectableProviders) { provider in
                Button {
                    viewModel.selectProvider(provider)
                    showProviderPicker = false
                } label: {
                    HStack(spacing: Spacing.sm) {
                        providerLogo(provider.id)
                        Text(provider.name)
                            .foregroundStyle(palette.textPrimary)
                        Spacer(minLength: Spacing.md)
                        if provider.id == currentProvider.id {
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
