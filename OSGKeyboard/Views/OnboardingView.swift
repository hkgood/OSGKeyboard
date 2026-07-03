// OnboardingView.swift
// OSGKeyboard · Main App
//
// Five-step onboarding:
//   1) Welcome
//   2) Microphone permission
//   3) Speech recognition permission
//   4) Enable keyboard + Allow Full Access
//   5) Engine / API setup

import SwiftUI
import OSGKeyboardShared
import UIKit

private enum OnboardingPage: Int, CaseIterable {
    case welcome = 0
    case microphone
    case speech
    case keyboard
    case api

    static let count = 5
}

struct OnboardingView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject var config: ProviderConfig
    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    // v0.2.0: no on-device model downloads remain, so the API setup
    // page no longer needs a ModelManager / pendingDownload binding.

    private var currentPage: OnboardingPage {
        OnboardingPage(rawValue: config.onboardingPage) ?? .welcome
    }

    var body: some View {
        GeometryReader { geo in
            let gradientHeight = geo.size.height * 0.28 + geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    progressHeader
                        .padding(.top, Spacing.md)
                        .padding(.bottom, Spacing.sm)

                    Group {
                        switch currentPage {
                        case .welcome:
                            WelcomePage()
                        case .microphone:
                            MicPermissionPage(status: $micStatus, showsPreface: speechStatus != .granted)
                        case .speech:
                            SpeechPermissionPage(status: $speechStatus)
                        case .keyboard:
                            EnableKeyboardPage()
                        case .api:
                            APISetupPage(config: config)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                    pageDots
                        .padding(.bottom, Spacing.md)

                    bottomBar
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.lg)
                }

                onboardingHeaderGradient(height: gradientHeight)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            if config.onboardingPage < 0 || config.onboardingPage >= OnboardingPage.count {
                config.onboardingPage = 0
            }
            applyOnboardingDefaultsIfNeeded()
            refreshPermissionStatuses()
            snapToVisiblePageIfNeeded()
            // v0.2.0: no on-device ASR weights to warm up — iOS
            // `SpeechAnalyzer` ships with iOS 26 and is always ready.
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshPermissionStatuses() }
        }
        .onChange(of: micStatus) { previous, current in
            guard currentPage == .microphone, current == .granted, previous != .granted else { return }
            advanceAfterPermissionGrant()
        }
        .onChange(of: speechStatus) { previous, current in
            guard currentPage == .speech, current == .granted, previous != .granted else { return }
            advanceAfterPermissionGrant()
        }
    }

    // MARK: - Navigation helpers

    private func applyOnboardingDefaultsIfNeeded() {
        guard !config.hasCompletedOnboarding, config.onboardingPage == 0 else { return }
        // First-time users with no API key: default to local for a faster path.
        // v0.2.0: no per-user ASR backend selection — iOS `SpeechAnalyzer`
        // is the only local option, so we don't need to mutate
        // `config.localASRBackend` here.
        if config.apiKey.isEmpty, config.engineMode == "cloud" {
            config.engineMode = "local"
        }
    }

    /// v0.2.0: with iOS `SpeechAnalyzer` as the only local backend,
    /// the "local engine ready" check is always true — there is nothing
    /// for the user to download. Kept as a derived property so the
    /// existing call sites (which feed the Done button state) compile
    /// unchanged.
    private var localModelNeedsAttention: Bool { false }

    private func shouldShowPage(_ page: OnboardingPage) -> Bool {
        switch page {
        case .microphone: return micStatus != .granted
        case .speech: return speechStatus != .granted
        case .keyboard: return !keyboardReady
        default: return true
        }
    }

    private func nextVisiblePage(after page: Int) -> Int? {
        guard page + 1 < OnboardingPage.count else { return nil }
        for index in (page + 1)..<OnboardingPage.count {
            guard let candidate = OnboardingPage(rawValue: index) else { continue }
            if shouldShowPage(candidate) { return index }
        }
        return nil
    }

    private func previousVisiblePage(before page: Int) -> Int? {
        guard page > 0 else { return nil }
        for index in stride(from: page - 1, through: 0, by: -1) {
            guard let candidate = OnboardingPage(rawValue: index) else { continue }
            if shouldShowPage(candidate) { return index }
        }
        return nil
    }

    private func snapToVisiblePageIfNeeded() {
        guard let page = OnboardingPage(rawValue: config.onboardingPage) else { return }
        guard !shouldShowPage(page) else { return }
        if let next = nextVisiblePage(after: config.onboardingPage) {
            config.onboardingPage = next
        } else if let previous = previousVisiblePage(before: config.onboardingPage) {
            config.onboardingPage = previous
        }
    }

    private func advanceAfterPermissionGrant() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard currentPage == .microphone || currentPage == .speech else { return }
            refreshPermissionStatuses()
            withAnimation(Motion.soft) {
                if let next = nextVisiblePage(after: config.onboardingPage) {
                    config.onboardingPage = next
                }
            }
        }
    }

    private func advancePage() {
        refreshPermissionStatuses()
        withAnimation(Motion.soft) {
            if isLastPage {
                config.hasCompletedOnboarding = true
            } else if let next = nextVisiblePage(after: config.onboardingPage) {
                config.onboardingPage = next
            } else {
                config.hasCompletedOnboarding = true
            }
        }
    }

    private func onboardingHeaderGradient(height: CGFloat) -> some View {
        LinearGradient(
            colors: localModelNeedsAttention
                ? [
                    palette.warning.opacity(0.32),
                    palette.warning.opacity(0.12),
                    palette.background.opacity(0)
                ]
                : [
                    palette.textTertiary.opacity(0.14),
                    palette.textTertiary.opacity(0.05),
                    palette.background.opacity(0)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(Motion.soft, value: localModelNeedsAttention)
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
        keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    }

    private var progressHeader: some View {
        Text(
            String(
                format: AppL10n.string("onboarding.progress"),
                config.onboardingPage + 1,
                OnboardingPage.count
            )
        )
        .font(TypeStyle.caption)
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<OnboardingPage.count, id: \.self) { i in
                Capsule()
                    .fill(i == config.onboardingPage ? palette.accent : palette.textTertiary.opacity(0.28))
                    .frame(width: i == config.onboardingPage ? 18 : 6, height: 6)
                    .animation(Motion.quick, value: config.onboardingPage)
            }
        }
    }

    private var isLastPage: Bool { config.onboardingPage == OnboardingPage.api.rawValue }

    private var canAdvance: Bool {
        switch currentPage {
        case .welcome, .keyboard:
            return !isLastPage || onboardingCompleteReady
        case .api:
            return !isLastPage || onboardingCompleteReady
        case .microphone:
            return micStatus != .undetermined
        case .speech:
            return speechStatus != .undetermined
        }
    }

    private var onboardingCompleteReady: Bool {
        // v0.2.0: the local engine uses iOS `SpeechAnalyzer`, which is
        // always available — no model download gate. The cloud engine
        // still requires base URL + API key + model.
        if config.isLocalEngine { return true }
        return config.isConfigured
    }

    private var primaryActionTitle: String {
        if isLastPage {
            return AppL10n.string("common.done")
        }
        switch currentPage {
        case .microphone where micStatus == .granted,
             .speech where speechStatus == .granted:
            return AppL10n.string("common.continue")
        default:
            return AppL10n.string("common.next")
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: Spacing.sm) {
            if let previous = previousVisiblePage(before: config.onboardingPage) {
                Button {
                    withAnimation(Motion.soft) { config.onboardingPage = previous }
                } label: {
                    Text("common.back")
                        .font(TypeStyle.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                                .stroke(palette.dividerStrong, lineWidth: 0.5)
                        )
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
            }

            Button { advancePage() } label: {
                Text(primaryActionTitle)
                    .font(TypeStyle.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        canAdvance ? palette.accent : palette.surfaceElevated,
                        in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    )
                    .foregroundStyle(canAdvance ? palette.textOnAccent : palette.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance)
        }
    }
}

// MARK: - Shared onboarding chrome

private struct OnboardingHeroIcon: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let systemName: String
    var circleSize: CGFloat = 88
    var iconSize: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(palette.accentMuted)
                .frame(width: circleSize, height: circleSize)
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(palette.accent)
        }
    }
}

private enum OnboardingLayoutMetrics {
    /// Matches welcome page: hero → title block, and title block → next block.
    static let heroTextGap: CGFloat = Spacing.hero
}

/// Title + subtitle styling aligned with the welcome page.
private struct OnboardingTitleBlock: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil
    var secondarySubtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(title)
                .font(TypeStyle.title3)
                .foregroundStyle(palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
            }
            if let secondarySubtitle {
                Text(secondarySubtitle)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.xl)
    }
}

// MARK: - Welcome

private struct WelcomePage: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @State private var logoAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("osglogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 168, maxHeight: 48)
                .opacity(logoAppeared ? 1 : 0)
                .offset(y: logoAppeared ? 0 : 14)
                .scaleEffect(logoAppeared ? 1 : 0.9)
                .accessibilityHidden(true)
                .onAppear {
                    withAnimation(.spring(response: 0.75, dampingFraction: 0.82)) {
                        logoAppeared = true
                    }
                }

            OnboardingTitleBlock(
                title: "onboarding.welcome.tagline",
                subtitle: "onboarding.welcome.subtitle",
                secondarySubtitle: "onboarding.welcome.subtitle2"
            )
            .opacity(logoAppeared ? 1 : 0)
            .offset(y: logoAppeared ? 0 : 10)
            .padding(.top, OnboardingLayoutMetrics.heroTextGap)
            .animation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.12), value: logoAppeared)

            if let url = LegalLinks.privacyPolicyURL {
                Link(destination: url) {
                    Text("legal.privacyPolicy")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.accent)
                }
                .padding(.top, Spacing.xxxl)
                .opacity(logoAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.45).delay(0.28), value: logoAppeared)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Permission pages

private struct MicPermissionPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Binding var status: AppPermissions.MicStatus
    var showsPreface: Bool = false
    @State private var isRequesting = false

    var body: some View {
        PermissionPageLayout(
            icon: "mic.fill",
            title: "onboarding.permission.mic.title",
            detail: "onboarding.permission.mic.body",
            preface: showsPreface ? "onboarding.permission.preface" : nil,
            status: statusLabel,
            statusColor: statusColor,
            primaryTitle: primaryButtonTitle,
            primaryDisabled: isRequesting || (status == .granted),
            onPrimary: { Task { await request() } },
            deniedHint: status == .denied ? "onboarding.permission.mic.deniedHint" : nil
        )
        .onAppear { status = AppPermissions.micStatus }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status = AppPermissions.micStatus
        }
    }

    private var statusLabel: LocalizedStringKey {
        switch status {
        case .undetermined: return "onboarding.permission.status.undetermined"
        case .granted: return "onboarding.permission.status.granted"
        case .denied: return "onboarding.permission.status.denied"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return palette.accent
        case .denied: return palette.warning
        case .undetermined: return palette.textTertiary
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        switch status {
        case .granted: return "onboarding.permission.status.granted"
        case .denied: return "onboarding.permission.openSettings"
        case .undetermined: return "onboarding.permission.mic.allow"
        }
    }

    private func request() async {
        if status == .denied {
            AppPermissions.openSystemSettings()
            return
        }
        isRequesting = true
        _ = await AppPermissions.requestMicrophone()
        status = AppPermissions.micStatus
        isRequesting = false
    }
}

private struct SpeechPermissionPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Binding var status: AppPermissions.SpeechStatus
    @State private var isRequesting = false

    var body: some View {
        PermissionPageLayout(
            icon: "waveform.badge.mic",
            title: "onboarding.permission.speech.title",
            detail: "onboarding.permission.speech.body",
            status: statusLabel,
            statusColor: statusColor,
            primaryTitle: primaryButtonTitle,
            primaryDisabled: isRequesting || status == .granted,
            onPrimary: { Task { await request() } },
            deniedHint: speechDenied ? "onboarding.permission.speech.deniedHint" : nil
        )
        .onAppear { status = AppPermissions.speechStatus }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            status = AppPermissions.speechStatus
        }
    }

    private var speechDenied: Bool {
        switch status {
        case .denied, .restricted: return true
        default: return false
        }
    }

    private var statusLabel: LocalizedStringKey {
        switch status {
        case .undetermined: return "onboarding.permission.status.undetermined"
        case .granted: return "onboarding.permission.status.granted"
        case .denied, .restricted: return "onboarding.permission.status.denied"
        }
    }

    private var statusColor: Color {
        switch status {
        case .granted: return palette.accent
        case .denied, .restricted: return palette.warning
        case .undetermined: return palette.textTertiary
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        switch status {
        case .granted: return "onboarding.permission.status.granted"
        case .denied, .restricted: return "onboarding.permission.openSettings"
        case .undetermined: return "onboarding.permission.speech.allow"
        }
    }

    private func request() async {
        if speechDenied {
            AppPermissions.openSystemSettings()
            return
        }
        isRequesting = true
        _ = await AppPermissions.requestSpeechRecognition()
        status = AppPermissions.speechStatus
        isRequesting = false
    }
}

private struct PermissionPageLayout: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var preface: LocalizedStringKey? = nil
    let status: LocalizedStringKey
    let statusColor: Color
    let primaryTitle: LocalizedStringKey
    let primaryDisabled: Bool
    let onPrimary: () -> Void
    var secondaryTitle: LocalizedStringKey? = nil
    var onSecondary: (() -> Void)? = nil
    var deniedHint: LocalizedStringKey? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.lg)

                if let preface {
                    Text(preface)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.lg)
                }

                OnboardingHeroIcon(systemName: icon, circleSize: 96, iconSize: 40)

                OnboardingTitleBlock(title: title, subtitle: detail)
                    .padding(.top, OnboardingLayoutMetrics.heroTextGap)

                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(status)
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, OnboardingLayoutMetrics.heroTextGap)

                if let deniedHint {
                    Text(deniedHint)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.warning)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.top, Spacing.md)
                }

                VStack(spacing: Spacing.sm) {
                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .primaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(primaryDisabled)

                    if let secondaryTitle, let onSecondary {
                        Button(action: onSecondary) {
                            Text(secondaryTitle)
                                .secondaryButton()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xl)

                Spacer(minLength: Spacing.lg)
            }
        }
    }
}

// MARK: - Enable keyboard

private struct EnableKeyboardPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.lg)

                OnboardingHeroIcon(systemName: "keyboard.fill", circleSize: 96, iconSize: 40)

                OnboardingTitleBlock(
                    title: "onboarding.enable.title",
                    subtitle: "onboarding.enable.fullAccessNote"
                )
                .padding(.top, OnboardingLayoutMetrics.heroTextGap)

                VStack(alignment: .leading, spacing: Spacing.lg) {
                    step(num: 1, text: AppL10n.string("onboarding.enable.step1"))
                    step(num: 2, text: AppL10n.string("onboarding.enable.step2"))
                    switchKeyboardStep(num: 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.top, OnboardingLayoutMetrics.heroTextGap)

                PrivacyInfoCard(
                    title: "settings.privacy.fullAccess.title",
                    bodyText: "settings.privacy.fullAccess.body"
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

                Button {
                    AppPermissions.openSystemSettings()
                } label: {
                    Label(LocalizedStringKey("onboarding.enable.openSettings"), systemImage: "arrow.up.right.square")
                        .primaryButton()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.xxxl)

                Spacer(minLength: Spacing.lg)
            }
        }
    }

    private func step(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            stepLabel(num)
            Text(text)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func switchKeyboardStep(num: Int) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            stepLabel(num)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("onboarding.enable.step3.prefix")
                Image(systemName: "globe")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[.bottom] - dimensions.height * 0.12
                    }
                Text("onboarding.enable.step3.suffix")
            }
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepLabel(_ num: Int) -> some View {
        Text("\(num)")
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .frame(width: 20, alignment: .leading)
    }
}

// MARK: - API setup

private struct APISetupPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                OnboardingHeroIcon(systemName: "cpu", circleSize: 72, iconSize: 30)
                    .padding(.top, Spacing.xl)

                OnboardingTitleBlock(title: "onboarding.api.title")
                    .padding(.horizontal, Spacing.lg)

                EnginePickerSection(config: config)
                    .padding(.horizontal, Spacing.lg)

                if config.engineMode == "cloud" {
                    ProviderPickerSection(config: config)
                        .padding(.horizontal, Spacing.lg)
                    APISettingsCard(config: config)
                        .padding(.horizontal, Spacing.lg)
                } else {
                    // v0.2.0: local engine is iOS `SpeechAnalyzer` only.
                    // Surface the cloud-polish toggle and a one-line
                    // reminder that the iOS ASR is bundled with iOS 26
                    // (no download step).
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("onboarding.api.localModels.hint")
                            .font(TypeStyle.caption2)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        LocalModelsGroup(config: config)
                            .background(
                                palette.surface,
                                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                                    .stroke(palette.divider, lineWidth: 0.5)
                            )
                    }
                    .padding(.horizontal, Spacing.lg)
                }

            }
            .padding(.bottom, Spacing.xxxl)
        }
    }
}
