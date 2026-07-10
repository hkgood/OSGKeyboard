// MacOnboardingView.swift
// OSGKeyboard · Mac
//
// A short first-run setup for the macOS app. It is intentionally separate
// from iOS onboarding because Mac needs Accessibility and optional Sherpa setup.
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
    case cloudAPI
    case localModel

    var systemImage: String {
        switch self {
        case .welcome: return "sparkles"
        case .microphone: return "mic.fill"
        case .accessibility: return "accessibility"
        case .engine: return "switch.2"
        case .cloudAPI: return "key.fill"
        case .localModel: return "arrow.down.circle.fill"
        }
    }
}

@MainActor
private final class MacOnboardingViewModel: ObservableObject {
    @Published var step: MacOnboardingStep = .welcome
    @Published var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var accessibilityTrusted = MacTextInsertionService.isAccessibilityTrusted
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
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityTrusted = MacTextInsertionService.isAccessibilityTrusted
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        }
    }

    func openAccessibilitySettings() {
        _ = MacTextInsertionService.requestAccessibilityIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshAccessibilitySoon()
    }

    func refreshAccessibilitySoon() {
        accessibilityTrusted = MacTextInsertionService.isAccessibilityTrusted
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.accessibilityTrusted = MacTextInsertionService.isAccessibilityTrusted
        }
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
    @State private var contentAppeared = false

    private var lang: AppUILanguage { viewModel.config.uiLanguage }

    private var visibleSteps: [MacOnboardingStep] {
        if viewModel.config.engineMode == "cloud" {
            return [.welcome, .microphone, .accessibility, .engine, .cloudAPI]
        }
        return [.welcome, .microphone, .accessibility, .engine, .localModel]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                background(height: geo.size.height)

                VStack(spacing: 0) {
                    Spacer(minLength: Spacing.xl)

                    hero
                        .id(model.step)
                        .transition(stepTransition)

                    Spacer(minLength: Spacing.lg)

                    progressDots
                        .padding(.bottom, Spacing.lg)

                    bottomBar
                        .padding(.horizontal, Spacing.xxxl)
                        .padding(.bottom, Spacing.xxl)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: MacMetrics.windowMinWidth, minHeight: MacMetrics.windowMinHeight)
        .onAppear {
            applyDefaults()
            model.reload()
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                contentAppeared = true
            }
        }
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
            Image("OSGBrandMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)
                .foregroundStyle(colorScheme == .dark ? Color.white : palette.accent)
                .accessibilityLabel("OSGKeyboard")
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
                isGranted: model.micStatus == .authorized,
                grantedText: MacL10n.string("mac.onboarding.microphone.granted", language: lang),
                neededText: MacL10n.string("mac.onboarding.microphone.needed", language: lang)
            )
        case .accessibility:
            permissionCard(
                isGranted: model.accessibilityTrusted,
                grantedText: MacL10n.string("mac.onboarding.accessibility.granted", language: lang),
                neededText: MacL10n.string("mac.onboarding.accessibility.needed", language: lang)
            )
        case .engine:
            enginePicker
        case .cloudAPI:
            cloudAPIFields
        case .localModel:
            localModelPanel
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
        .overlay(cardShape.stroke(palette.divider, lineWidth: 0.5))
    }

    private func permissionCard(isGranted: Bool, grantedText: String, neededText: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: isGranted ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isGranted ? palette.accent : palette.warning)

            Text(isGranted ? grantedText : neededText)
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textPrimary)

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
        .overlay(cardShape.stroke((isGranted ? palette.accent : palette.warning).opacity(0.25), lineWidth: 1))
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
            .overlay(cardShape.stroke(selected ? palette.accent.opacity(0.5) : palette.divider, lineWidth: selected ? 1 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var cloudAPIFields: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker(MacL10n.string("mac.settings.service", language: lang), selection: providerBinding) {
                ForEach(viewModel.selectableProviders) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            SecureField(text: $viewModel.config.apiKey, prompt: Text(verbatim: "sk-...")) {
                Text(MacL10n.string("mac.settings.apiKey", language: lang))
            }
            .labelsHidden()
            .macFieldStyle()

            TextField(text: $viewModel.config.model, prompt: Text(verbatim: "")) {
                Text(MacL10n.string("mac.settings.model", language: lang))
            }
            .labelsHidden()
            .macFieldStyle()

            Label(MacL10n.string("mac.onboarding.cloud.skipHint", language: lang), systemImage: "info.circle")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
        .overlay(cardShape.stroke(palette.divider, lineWidth: 0.5))
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
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity)
        .background(cardShape.fill(palette.surface))
        .overlay(cardShape.stroke(palette.divider, lineWidth: 0.5))
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

            Spacer(minLength: 0)

            primaryButton(primaryButtonTitle, disabled: model.isInstalling && model.step == .localModel) {
                primaryAction()
            }
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ titleText: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleText)
                .font(TypeStyle.headline)
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
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        .stroke(palette.dividerStrong, lineWidth: 0.5)
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
        case .cloudAPI: return MacL10n.string("mac.onboarding.cloud.title", language: lang)
        case .localModel: return MacL10n.string("mac.onboarding.model.title", language: lang)
        }
    }

    private var subtitle: String {
        switch model.step {
        case .welcome: return MacL10n.string("mac.onboarding.welcome.subtitle", language: lang)
        case .microphone: return MacL10n.string("mac.onboarding.microphone.subtitle", language: lang)
        case .accessibility: return MacL10n.string("mac.onboarding.accessibility.subtitle", language: lang)
        case .engine: return MacL10n.string("mac.onboarding.engine.subtitle", language: lang)
        case .cloudAPI: return MacL10n.string("mac.onboarding.cloud.subtitle", language: lang)
        case .localModel: return MacL10n.string("mac.onboarding.model.subtitle", language: lang)
        }
    }

    private var primaryButtonTitle: String {
        switch model.step {
        case .microphone where model.micStatus != .authorized:
            return MacL10n.string("mac.onboarding.microphone.allow", language: lang)
        case .accessibility where !model.accessibilityTrusted:
            return MacL10n.string("mac.onboarding.accessibility.open", language: lang)
        case .cloudAPI:
            return MacL10n.string("mac.onboarding.finish", language: lang)
        case .localModel:
            return MacL10n.string(model.isDefaultModelInstalled ? "mac.onboarding.finish" : "mac.onboarding.skipForNow", language: lang)
        default:
            return isLastStep ? MacL10n.string("mac.onboarding.finish", language: lang) : MacL10n.string("mac.onboarding.next", language: lang)
        }
    }

    private var localModelSubtitle: String {
        if model.isDefaultModelInstalled {
            return MacL10n.string("mac.localASR.installed", language: lang)
        }
        guard let model = model.defaultModel else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(model.sizeBytes), countStyle: .file)
    }

    private var providerBinding: Binding<String> {
        Binding(
            get: { viewModel.config.providerId },
            set: { newId in
                guard let provider = viewModel.selectableProviders.first(where: { $0.id == newId }) else { return }
                viewModel.selectProvider(provider)
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
        model.step != .welcome && !model.isInstalling
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
        case .microphone where model.micStatus != .authorized:
            model.requestMicrophone()
        case .accessibility where !model.accessibilityTrusted:
            model.openAccessibilitySettings()
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
