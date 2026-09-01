// MacOnboardingView.swift
// OSGKeyboard · Mac
//
// A short first-run setup for the macOS app. It is intentionally separate
// from iOS onboarding because Mac needs Accessibility and local-model setup.
// The current local runtime defaults to Qwen3 MLX with Apple Speech fallback;
// Sherpa identifiers and install records are retained only for migration compatibility.
//
// Step order mirrors iOS: permissions → engine → the recognition credentials
// that engine needs → the polish LLM. Speech recognition and polishing are two
// different providers with two different keys (iOS splits them across
// `APISetupPage` and `PolishSetupPage`), so they get one step each here too.
//
// Visual language mirrors the iOS onboarding: an ambient top gradient, a
// glowing hero icon, a large title block, and elongated capsule progress
// dots — all carried by whitespace and a single accent colour.

import AppKit
import AVFoundation
import SwiftUI

enum MacOnboardingState {
    static let storageKey = "mac.hasCompletedOnboarding"
}

private enum MacOnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case accessibility
    case engine
    /// Cloud *speech recognition* credentials — shown only in cloud mode.
    case cloudASR
    /// Local ASR model download — shown only in local mode.
    case localModel
    /// Polish / translation / AI LLM credentials — shown in both modes.
    case polish

    var systemImage: String {
        switch self {
        case .welcome: return "sparkles"
        case .microphone: return "mic.fill"
        case .accessibility: return "accessibility"
        case .engine: return "switch.2"
        case .cloudASR: return "waveform"
        case .localModel: return "arrow.down.circle.fill"
        case .polish: return "wand.and.stars"
        }
    }
}

@MainActor
private final class MacOnboardingViewModel: ObservableObject {
    @Published var step: MacOnboardingStep = .welcome
    @Published var catalog: LocalASRCatalogDocument?
    @Published var installProgress = LocalASRModelInstallProgress.idle
    @Published var isInstalling = false
    @Published var statusMessage = ""

    private let manager = LocalASRModelManager.shared
    private var progressPollTask: Task<Void, Never>?

    deinit {
        progressPollTask?.cancel()
    }

    var defaultModel: LocalASRModelDefinition? {
        guard let catalog else { return nil }
        return catalog.models.first { $0.id == catalog.defaultModelId }
    }

    var isDefaultModelInstalled: Bool {
        guard let defaultModel else { return false }
        return MacLocalASRService.isModelInstalled(defaultModel)
    }

    func reload() {
        catalog = try? LocalASRModelCatalog.loadBundled()
    }

    func installDefaultModel() {
        guard let catalog, let model = defaultModel, !isInstalling else { return }
        statusMessage = ""
        isInstalling = true
        startProgressPolling()
        Task {
            do {
                try await manager.installModel(model, catalog: catalog)
                installProgress = await manager.currentProgress()
                selectInstalledModel(model.id, catalog: catalog)
                statusMessage = MacL10n.string("mac.onboarding.model.done")
            } catch {
                installProgress = await manager.currentProgress()
                statusMessage = error.localizedDescription
            }
            isInstalling = false
            stopProgressPolling()
            reload()
        }
    }

    func progressLabel(language: AppUILanguage) -> String {
        let phase: String
        switch installProgress.phase {
        case .idle: return installProgress.message
        case .downloading: phase = MacL10n.string("mac.localASR.phase.downloading", language: language)
        case .paused: phase = MacL10n.string("mac.localASR.phase.paused", language: language)
        case .extracting: phase = MacL10n.string("mac.localASR.phase.extracting", language: language)
        case .validating: phase = MacL10n.string("mac.localASR.phase.validating", language: language)
        case .finalizing: phase = MacL10n.string("mac.localASR.phase.finalizing", language: language)
        case .failed: phase = MacL10n.string("mac.localASR.phase.failed", language: language)
        case .completed: phase = MacL10n.string("mac.localASR.phase.completed", language: language)
        }
        guard !installProgress.message.isEmpty else { return phase }
        return "\(phase) · \(installProgress.message)"
    }

    private func selectInstalledModel(_ modelId: String, catalog: LocalASRCatalogDocument) {
        MacLocalASRPreferences.selectedModelId = modelId
        var manifest = LocalASRInstalledManifestIO.load(defaultModelId: catalog.defaultModelId)
        manifest.selectedModelId = modelId
        manifest.updatedAt = Date()
        try? LocalASRInstalledManifestIO.save(manifest)
    }

    private func startProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = Task { [weak self] in
            while !Task.isCancelled {
                let current = await LocalASRModelManager.shared.currentProgress()
                await MainActor.run { self?.installProgress = current }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func stopProgressPolling() {
        progressPollTask?.cancel()
        progressPollTask = nil
    }
}

// MARK: - Root

struct MacOnboardingView: View {
    @ObservedObject var viewModel: MacDictationViewModel
    @Binding var hasCompletedOnboarding: Bool

    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = MacOnboardingViewModel()
    // Microphone and Accessibility are both granted outside the app. Poll for
    // them rather than sampling once — see `MacPermissionMonitor`.
    @StateObject private var permissions = MacPermissionMonitor()
    @State private var contentAppeared = false

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    private var visibleSteps: [MacOnboardingStep] {
        var steps: [MacOnboardingStep] = [.welcome, .microphone, .accessibility, .engine]
        steps.append(viewModel.config.engineMode == "cloud" ? .cloudASR : .localModel)
        // Polishing runs on a cloud LLM in both engine modes, so its provider
        // is configured either way.
        steps.append(.polish)
        return steps
    }

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                background(height: geo.size.height)
            }

            VStack(spacing: 0) {
                // The hero scrolls; the dots and the bottom bar are pinned so
                // the primary action can never fall below the window edge —
                // which is exactly what happened at the minimum window size.
                GeometryReader { scrollGeo in
                    ScrollView {
                        hero
                            .id(model.step)
                            .transition(stepTransition)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.xl)
                            .frame(minHeight: scrollGeo.size.height, alignment: .center)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                progressDots
                    .padding(.bottom, Spacing.lg)

                bottomBar
                    .padding(.horizontal, Spacing.xxxl)
                    .padding(.bottom, Spacing.xxl)
            }
        }
        .frame(minWidth: MacMetrics.windowMinWidth, minHeight: MacMetrics.windowMinHeight)
        .onAppear {
            applyDefaults()
            model.reload()
            permissions.start()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                contentAppeared = true
            }
        }
        .onDisappear { permissions.stop() }
    }

    // MARK: Background

    private func background(height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            palette.background.ignoresSafeArea()

            LinearGradient(
                colors: [
                    palette.accent.opacity(0.12),
                    palette.accent.opacity(0.03),
                    palette.background.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height * 0.42)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    // MARK: Hero + content

    private var hero: some View {
        VStack(spacing: Spacing.lg) {
            heroIcon

            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(TypeStyle.title2)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }

            stepContent
                .frame(maxWidth: 460)
                .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xxl)
        .opacity(contentAppeared ? 1 : 0)
        .offset(y: contentAppeared ? 0 : 12)
    }

    @ViewBuilder
    private var heroIcon: some View {
        if model.step == .welcome {
            ZStack {
                SonicParticleField()
                    .frame(width: 300, height: 300)

                Image("OSGBrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 128, height: 128)
                    .foregroundStyle(
                        colorScheme == .dark ? OSGColor.fixedLightContent : palette.accent
                    )
                    .accessibilityLabel("OSGKeyboard")
                    .allowsHitTesting(false)
            }
            .frame(width: 300, height: 300)
        } else {
            ZStack {
                Circle()
                    .fill(palette.accentGlow)
                    .frame(width: 116, height: 116)
                    .blur(radius: 26)

                Circle()
                    .fill(palette.accentMuted)
                    .frame(width: 92, height: 92)
                    .overlay(Circle().stroke(palette.accent.opacity(0.25), lineWidth: 1))

                Image(systemName: model.step.systemImage)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome:
            featureList
        case .microphone:
            permissionCard(
                isGranted: permissions.microphoneStatus == .authorized,
                grantedText: MacL10n.string("mac.onboarding.microphone.granted", language: lang),
                neededText: MacL10n.string("mac.onboarding.microphone.needed", language: lang)
            )
        case .accessibility:
            permissionCard(
                isGranted: permissions.isAccessibilityTrusted,
                grantedText: MacL10n.string("mac.onboarding.accessibility.granted", language: lang),
                neededText: MacL10n.string("mac.onboarding.accessibility.needed", language: lang)
            )
        case .engine:
            enginePicker
        case .cloudASR:
            cloudASRFields
        case .localModel:
            localModelPanel
        case .polish:
            polishFields
        }
    }

    private var featureList: some View {
        VStack(spacing: Spacing.sm) {
            featureRow("lock.shield.fill", MacL10n.string("mac.onboarding.welcome.privacy", language: lang))
            featureRow("option", MacL10n.string("mac.onboarding.welcome.hotkey", language: lang))
            featureRow("cpu", MacL10n.string("mac.onboarding.welcome.local", language: lang))
        }
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 26, height: 26)
                .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(text)
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
    }

    private func permissionCard(isGranted: Bool, grantedText: String, neededText: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isGranted ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isGranted ? palette.accent : palette.warning)

            Text(isGranted ? grantedText : neededText)
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
        .animation(Motion.quick, value: isGranted)
    }

    private var enginePicker: some View {
        VStack(spacing: Spacing.sm) {
            engineRow(
                title: MacL10n.string("mac.settings.localEngine", language: lang),
                subtitle: MacL10n.string("mac.onboarding.engine.localDesc", language: lang),
                systemImage: "cpu",
                selected: viewModel.config.engineMode == "local"
            ) { setEngine("local") }

            engineRow(
                title: MacL10n.string("mac.settings.cloudEngine", language: lang),
                subtitle: MacL10n.string("mac.onboarding.engine.cloudDesc", language: lang),
                systemImage: "cloud.fill",
                selected: viewModel.config.engineMode == "cloud"
            ) { setEngine("cloud") }
        }
    }

    private func engineRow(
        title: String,
        subtitle: String,
        systemImage: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? palette.accent : palette.textTertiary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? palette.accent : palette.textTertiary.opacity(0.6))
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(cardShape.fill(selected ? palette.accentMuted : palette.surface))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Cloud speech-recognition credentials. Distinct from `polishFields`
    /// below: this writes the `asr*` config, and its provider list is the
    /// cloud-ASR allowlist, not the LLM presets.
    private var cloudASRFields: some View {
        credentialCard(
            providerLabel: MacL10n.string("mac.settings.asrService", language: lang),
            providers: viewModel.asrSelectableProviders,
            providerSelection: asrProviderBinding,
            keyLabel: MacL10n.string("mac.settings.asrApiKey", language: lang),
            key: $viewModel.config.asrApiKey,
            modelLabel: MacL10n.string("mac.settings.asrModel", language: lang),
            modelPlaceholder: CloudASRModelCatalog.defaultModel(for: viewModel.config.asrProviderId),
            model: $viewModel.config.asrModel,
            hint: MacL10n.string("mac.onboarding.cloud.skipHint", language: lang)
        )
    }

    /// Polish / translation / AI LLM credentials — the step that was missing
    /// on Mac. Onboarding previously offered only the ASR provider list while
    /// writing into the *polish* config fields, so the two were never both set.
    private var polishFields: some View {
        credentialCard(
            providerLabel: MacL10n.string("mac.settings.service", language: lang),
            providers: viewModel.polishSelectableProviders,
            providerSelection: polishProviderBinding,
            keyLabel: MacL10n.string("mac.settings.apiKey", language: lang),
            key: $viewModel.config.apiKey,
            modelLabel: MacL10n.string("mac.settings.model", language: lang),
            modelPlaceholder: currentPolishProvider.defaultModel,
            model: $viewModel.config.model,
            hint: MacL10n.string("mac.onboarding.polish.skipHint", language: lang)
        )
    }

    private func credentialCard(
        providerLabel: String,
        providers: [LLMProvider],
        providerSelection: Binding<String>,
        keyLabel: String,
        key: Binding<String>,
        modelLabel: String,
        modelPlaceholder: String,
        model modelText: Binding<String>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            fieldLabel(providerLabel)
            MacInlinePicker(
                selection: providerSelection,
                options: providers.map {
                    MacInlinePickerOption(
                        value: $0.id,
                        label: ProviderDisplayName.name(for: $0.id, language: lang)
                    )
                },
                fillsWidth: true
            )

            fieldLabel(keyLabel)
            SecureField(text: key, prompt: Text(verbatim: "sk-…")) {
                Text(keyLabel)
            }
            .labelsHidden()
            .macFieldStyle()

            fieldLabel(modelLabel)
            TextField(text: modelText, prompt: Text(verbatim: modelPlaceholder)) {
                Text(modelLabel)
            }
            .labelsHidden()
            .macFieldStyle()

            Label(hint, systemImage: "info.circle")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(TypeStyle.caption)
            .foregroundStyle(palette.textTertiary)
    }

    private var localModelPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: model.isDefaultModelInstalled ? "checkmark.circle.fill" : "shippingbox.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(model.isDefaultModelInstalled ? palette.accent : palette.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.defaultModel?.displayName ?? MacL10n.string("mac.localASR.catalogMissing", language: lang))
                        .font(TypeStyle.bodyEmph)
                        .foregroundStyle(palette.textPrimary)
                    Text(localModelSubtitle)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: Spacing.sm)

                if !model.isDefaultModelInstalled, !model.isInstalling {
                    Button(MacL10n.string("mac.onboarding.model.download", language: lang)) {
                        model.installDefaultModel()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .disabled(model.defaultModel == nil)
                }
            }

            if model.isInstalling || model.installProgress.phase != .idle {
                ProgressView(value: model.installProgress.fraction)
                    .tint(palette.accent)
                Text(model.progressLabel(language: lang))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(TypeStyle.caption)
                    .foregroundStyle(model.isDefaultModelInstalled ? palette.accent : palette.warning)
            }

            Label(MacL10n.string("mac.onboarding.model.skipHint", language: lang), systemImage: "info.circle")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
    }

    // MARK: Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Array(visibleSteps.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(index == currentStepIndex ? palette.accent : palette.textTertiary.opacity(0.28))
                    .frame(width: index == currentStepIndex ? 22 : 6, height: 6)
            }
        }
        .animation(Motion.quick, value: currentStepIndex)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: Spacing.sm) {
            if canGoBack {
                secondaryButton(MacL10n.string("mac.onboarding.back", language: lang)) { goBack() }
            }

            if canSkipCurrentStep {
                secondaryButton(MacL10n.string("mac.onboarding.skipForNow", language: lang)) {
                    if isLastStep { finish() } else { goForward() }
                }
            }

            Spacer(minLength: Spacing.md)

            primaryButton(primaryButtonTitle, disabled: model.isInstalling && model.step == .localModel) {
                primaryAction()
            }
        }
        // Wide enough that three CJK labels ("上一步 · 暂时跳过 · 打开系统设置")
        // still fit on one line at the minimum window width.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ titleText: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // `lineLimit(1)` + `fixedSize` keep the label on one line: without
            // them a long CJK title ("打开系统设置") wrapped inside the fixed
            // 44pt pill and spilled outside the capsule.
            Text(titleText)
                .font(TypeStyle.headline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(disabled ? palette.textSecondary : palette.textOnAccent)
                .padding(.horizontal, Spacing.xxl)
                .frame(minWidth: 150, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .fill(disabled ? palette.surfaceElevated : palette.accent)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func secondaryButton(_ titleText: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleText)
                .font(TypeStyle.bodyEmph)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 44)
                .background(
                    palette.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Copy

    private var title: String {
        switch model.step {
        case .welcome: return MacL10n.string("mac.onboarding.welcome.title", language: lang)
        case .microphone: return MacL10n.string("mac.onboarding.microphone.title", language: lang)
        case .accessibility: return MacL10n.string("mac.onboarding.accessibility.title", language: lang)
        case .engine: return MacL10n.string("mac.onboarding.engine.title", language: lang)
        case .cloudASR: return MacL10n.string("mac.onboarding.cloud.title", language: lang)
        case .localModel: return MacL10n.string("mac.onboarding.model.title", language: lang)
        case .polish: return MacL10n.string("mac.onboarding.polish.title", language: lang)
        }
    }

    private var subtitle: String {
        switch model.step {
        case .welcome: return MacL10n.string("mac.onboarding.welcome.subtitle", language: lang)
        case .microphone: return MacL10n.string("mac.onboarding.microphone.subtitle", language: lang)
        case .accessibility: return MacL10n.string("mac.onboarding.accessibility.subtitle", language: lang)
        case .engine: return MacL10n.string("mac.onboarding.engine.subtitle", language: lang)
        case .cloudASR: return MacL10n.string("mac.onboarding.cloud.subtitle", language: lang)
        case .localModel: return MacL10n.string("mac.onboarding.model.subtitle", language: lang)
        case .polish: return MacL10n.string("mac.onboarding.polish.subtitle", language: lang)
        }
    }

    private var primaryButtonTitle: String {
        switch model.step {
        case .microphone where permissions.microphoneStatus != .authorized:
            return MacL10n.string("mac.onboarding.microphone.allow", language: lang)
        case .accessibility where !permissions.isAccessibilityTrusted:
            return MacL10n.string("mac.onboarding.accessibility.open", language: lang)
        case .localModel where !model.isDefaultModelInstalled:
            return MacL10n.string("mac.onboarding.skipForNow", language: lang)
        default:
            return isLastStep
                ? MacL10n.string("mac.onboarding.finish", language: lang)
                : MacL10n.string("mac.onboarding.next", language: lang)
        }
    }

    private var localModelSubtitle: String {
        if model.isDefaultModelInstalled {
            return MacL10n.string("mac.localASR.installed", language: lang)
        }
        guard let model = model.defaultModel else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(model.sizeBytes), countStyle: .file)
    }

    private var currentPolishProvider: LLMProvider {
        viewModel.polishSelectableProviders.first { $0.id == viewModel.config.providerId }
            ?? viewModel.polishSelectableProviders.first
            ?? LLMProvider.presets[0]
    }

    private var polishProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.config.providerId },
            set: { newId in
                guard let provider = viewModel.polishSelectableProviders
                    .first(where: { $0.id == newId }) else { return }
                viewModel.selectProvider(provider)
            }
        )
    }

    private var asrProviderBinding: Binding<String> {
        Binding(
            get: { viewModel.config.asrProviderId },
            set: { newId in
                guard let provider = viewModel.asrSelectableProviders
                    .first(where: { $0.id == newId }) else { return }
                viewModel.selectAsrProvider(provider)
            }
        )
    }

    // MARK: Derived

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10)),
            removal: .opacity.combined(with: .offset(y: -10))
        )
    }

    private var currentStepIndex: Int {
        visibleSteps.firstIndex(of: model.step) ?? 0
    }

    private var canGoBack: Bool {
        currentStepIndex > 0 && !model.isInstalling
    }

    private var canSkipCurrentStep: Bool {
        guard model.step != .welcome, !model.isInstalling else { return false }
        // On the local-model step the primary button already reads "Skip for
        // now"; a second identical button next to it reads as a bug.
        return !(model.step == .localModel && !model.isDefaultModelInstalled)
    }

    private var isLastStep: Bool {
        currentStepIndex == visibleSteps.count - 1
    }

    // MARK: Actions

    private func setEngine(_ mode: String) {
        withAnimation(Motion.quick) { viewModel.setEngineMode(mode) }
    }

    private func primaryAction() {
        switch model.step {
        case .microphone where permissions.microphoneStatus != .authorized:
            permissions.requestMicrophone()
        case .accessibility where !permissions.isAccessibilityTrusted:
            permissions.openAccessibilitySettings()
        default:
            if isLastStep { finish() } else { goForward() }
        }
    }

    private func goForward() {
        let nextIndex = min(currentStepIndex + 1, visibleSteps.count - 1)
        withAnimation(Motion.soft) { model.step = visibleSteps[nextIndex] }
    }

    private func goBack() {
        let previousIndex = max(currentStepIndex - 1, 0)
        withAnimation(Motion.soft) { model.step = visibleSteps[previousIndex] }
    }

    private func finish() {
        viewModel.selectedSection = .dashboard
        hasCompletedOnboarding = true
    }

    private func applyDefaults() {
        guard !hasCompletedOnboarding else { return }
        if viewModel.config.apiKey.isEmpty, viewModel.config.engineMode == "cloud" {
            viewModel.setEngineMode("local")
        }
    }
}
