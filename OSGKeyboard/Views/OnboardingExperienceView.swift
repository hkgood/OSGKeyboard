// OnboardingExperienceView.swift
// OSGKeyboard · Main App
//
// A short, outcome-led first run:
//   1) Explain the product and its data boundaries.
//   2) Request the two permissions needed by Flow.
//   3) Add the keyboard and verify Full Access on one screen — a settings
//      preview plus a type-to-verify field that auto-advances on success.
//   4) Teach four real features without requiring an account or API key.
//   5) Offer optional sign-in for the existing signup reward.
//   6) Celebrate the verified onboarding outcomes.

import OSGKeyboardShared
import SwiftUI
import UIKit

private enum OnboardingExperienceStep: Int, CaseIterable {
    case introduction = 0
    case permissions = 1
    // Setup + verification are now a single step: the user adds the keyboard
    // and confirms Full Access by typing in the same screen.
    case keyboard = 2
    // Retired: kept only so a value persisted mid-onboarding by an older build
    // resolves to `.keyboard` instead of an unknown step. Never navigated to.
    case keyboardSwitch = 5
    case practice = 3
    case complete = 4
    // Appended so all existing persisted values keep their original meaning.
    case loginReward = 6
}

private extension ManagedGatewayOOBEFeature {
    var progressKey: String {
        switch self {
        case .voiceInput:
            return "onboarding.experience.practice.progress.voice"
        case .clipboardTranslate:
            return "onboarding.experience.practice.progress.translate"
        case .clipboardReply:
            return "onboarding.experience.practice.progress.reply"
        case .askAI:
            return "onboarding.experience.practice.progress.askAI"
        }
    }

    var titleKey: String {
        switch self {
        case .voiceInput:
            return "onboarding.experience.practice.speakTitle"
        case .clipboardTranslate:
            return "onboarding.experience.practice.translateTitle"
        case .clipboardReply:
            return "onboarding.experience.practice.replyTitle"
        case .askAI:
            return "onboarding.experience.practice.askAITitle"
        }
    }

    var subtitleKey: String {
        switch self {
        case .voiceInput:
            return "onboarding.experience.practice.speakSubtitle"
        case .clipboardTranslate:
            return "onboarding.experience.practice.translateSubtitle"
        case .clipboardReply:
            return "onboarding.experience.practice.replySubtitle"
        case .askAI:
            return "onboarding.experience.practice.askAISubtitle"
        }
    }

    var editorSystemImage: String {
        switch self {
        case .voiceInput:
            return "message"
        case .clipboardTranslate:
            return "translate"
        case .clipboardReply:
            return "arrowshape.turn.up.left"
        case .askAI:
            return "sparkles.2"
        }
    }

    var next: ManagedGatewayOOBEFeature? {
        switch self {
        case .voiceInput:
            return .clipboardTranslate
        case .clipboardTranslate:
            return .clipboardReply
        case .clipboardReply:
            return .askAI
        case .askAI:
            return nil
        }
    }
}

#if DEBUG
private enum OOBEPreviewDestination {
    case practice(ManagedGatewayOOBEFeature)
    case loginReward
    case complete
}
#endif

struct OnboardingExperienceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var flowManager: FlowSessionManager
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @ObservedObject var config: ProviderConfig
    @ObservedObject private var deployment = RimeDeploymentController.shared
    private let oobeClient = OOBEClientInfrastructure.shared

    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var keyboardAppeared = KeyboardSetupBridge.hasAppeared
    @State private var keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    /// `nil` when iOS does not expose the enabled-keyboard list.
    @State private var keyboardInstalled = KeyboardInstallationProbe.isKeyboardEnabled()
    @State private var hasOpenedKeyboardSettings = false
    @State private var keyboardSettingsOpenFailed = false
    @State private var isRequestingPermissions = false
    @State private var keyboardSwitchText = ""
    @State private var keyboardVerificationTimedOut = false
    @State private var practiceText = ""
    @State private var practiceStartedAt: Date?
    @State private var isPreparingManagedPractice = false
    @State private var managedPracticeReady = false
    @State private var managedPracticeFailed = false
    @State private var practiceFeature = Self.initialPracticeFeature
    @State private var practiceSessionID: UUID?
    @State private var completedPracticeFeatures: Set<ManagedGatewayOOBEFeature> = []
    @State private var didCopyPracticeSample = false
    @State private var didRefreshLoginReward = false
    @State private var showsLoginRewardIcon = false
    @State private var showsCompleteIcon = false
    @State private var previewPageIndex = 0
    // Which edge a newly presented page slides in from. Forward navigation
    // enters from the trailing edge, back navigation from the leading edge, so
    // the motion always matches the direction the user is travelling.
    @State private var transitionEdge: Edge = .trailing
    @FocusState private var keyboardSwitchFieldFocused: Bool
    @FocusState private var practiceFieldFocused: Bool

    private static let migrationKey = "onboarding.experience.v2.migrated"
    private static let completedPracticeFeaturesKey =
        "onboarding.experience.oobe.completedFeatures.v1"

    private var currentStep: OnboardingExperienceStep {
        #if DEBUG
        switch activePreviewDestination {
        case .practice:
            return .practice
        case .loginReward:
            return .loginReward
        case .complete:
            return .complete
        case nil:
            break
        }
        #endif
        let resolved = OnboardingExperienceStep(rawValue: config.onboardingPage) ?? .introduction
        // The switch step was folded into `.keyboard`; a value left behind by an
        // older build lands on the merged setup screen.
        return resolved == .keyboardSwitch ? .keyboard : resolved
    }

    #if DEBUG
    private var activePreviewDestination: OOBEPreviewDestination? {
        guard Self.previewsAllScreensFromArguments else {
            return Self.previewDestination
        }
        return Self.allPreviewDestinations[
            min(previewPageIndex, Self.allPreviewDestinations.count - 1)
        ]
    }
    #endif

    private var isPreviewMode: Bool {
        #if DEBUG
        Self.isPreviewEnabled
        #else
        false
        #endif
    }

    private var previewLanguageOverride: AppUILanguage? {
        #if DEBUG
        isPreviewMode ? Self.previewLanguage : nil
        #else
        nil
        #endif
    }

    private var previewsAllScreens: Bool {
        #if DEBUG
        Self.previewsAllScreensFromArguments
        #else
        false
        #endif
    }

    private static var initialPracticeFeature: ManagedGatewayOOBEFeature {
        #if DEBUG
        if case let .practice(feature) = previewDestination {
            return feature
        }
        #endif
        return .voiceInput
    }

    #if DEBUG
    static var isPreviewEnabled: Bool {
        previewDestination != nil
    }

    static var previewLanguage: AppUILanguage {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshot-lang=en") {
            return .english
        }
        if arguments.contains("--screenshot-lang=zh") {
            return .chinese
        }
        return ProviderConfig.shared.uiLanguage
    }

    private static var previewsAllScreensFromArguments: Bool {
        ProcessInfo.processInfo.arguments.contains("--oobe-preview=all")
    }

    private static let allPreviewDestinations: [OOBEPreviewDestination] = [
        .practice(.voiceInput),
        .practice(.clipboardTranslate),
        .practice(.clipboardReply),
        .practice(.askAI),
        .loginReward,
        .complete
    ]

    private static var previewDestination: OOBEPreviewDestination? {
        let prefix = "--oobe-preview="
        guard let argument = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix(prefix) }
        ) else {
            return nil
        }
        switch String(argument.dropFirst(prefix.count)) {
        case "all":
            return .practice(.voiceInput)
        case "voice":
            return .practice(.voiceInput)
        case "translate":
            return .practice(.clipboardTranslate)
        case "reply":
            return .practice(.clipboardReply)
        case "ask-ai":
            return .practice(.askAI)
        case "login":
            return .loginReward
        case "complete":
            return .complete
        default:
            return nil
        }
    }
    #endif

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            OnboardingAmbientBackground()

            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentStep)
                    .transition(pageTransition)

                bottomAction
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .onAppear {
            guard !isPreviewMode else { return }
            migrateLegacyProgressIfNeeded()
            applyPrivacySafeDefaultsIfNeeded()
            if currentStep == .keyboard {
                KeyboardSetupBridge.invalidateSetupObservation()
            }
            refreshState()
            if currentStep == .practice {
                beginPractice()
            } else if currentStep == .loginReward {
                refreshLoginRewardIfNeeded()
            }
        }
        .onDisappear {
            guard !isPreviewMode else { return }
            endPractice()
        }
        .onChange(of: scenePhase) { _, phase in
            guard !isPreviewMode else { return }
            guard phase == .active else { return }
            refreshState()
            // Returning from Settings: keep the verify field ready so the
            // extension can run and report Full Access on this same screen.
            if currentStep == .keyboard, !keyboardReady {
                focusKeyboardSwitchField()
            }
            if currentStep == .practice {
                beginPracticeIfNeeded()
            }
        }
        .onChange(of: currentStep) { previous, current in
            guard !isPreviewMode else { return }
            if previous == .keyboard {
                keyboardSwitchFieldFocused = false
            }
            if previous == .practice {
                endPractice()
            }
            if current == .keyboard {
                // Re-verify from scratch: the previous record may predate the
                // user removing the keyboard or revoking Full Access.
                KeyboardSetupBridge.invalidateSetupObservation()
                keyboardVerificationTimedOut = false
                refreshState()
                focusKeyboardSwitchField()
            }
            if current == .practice {
                beginPractice()
            }
            if current == .loginReward {
                refreshLoginRewardIfNeeded()
            }
        }
        .onChange(of: accountSession.isSignedIn) { _, isSignedIn in
            guard !isPreviewMode else { return }
            guard isSignedIn, currentStep == .loginReward else { return }
            didRefreshLoginReward = false
            refreshLoginRewardIfNeeded()
        }
        .onChange(of: config.hasAcknowledgedCloudSharing) { _, acknowledged in
            guard !isPreviewMode else { return }
            guard acknowledged, currentStep == .practice else { return }
            prepareManagedPractice()
        }
        .task(id: currentStep) {
            guard !isPreviewMode else { return }
            switch currentStep {
            case .keyboard:
                await monitorKeyboardVerification()
            case .practice:
                await monitorPractice()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        switch currentStep {
        case .introduction:
            introductionPage
        case .permissions:
            permissionsPage
        case .keyboard, .keyboardSwitch:
            keyboardPage
        case .practice:
            practicePage
        case .loginReward:
            loginRewardPage
        case .complete:
            completePage
        }
    }

    /// Directional page transition: a page enters from the edge the user is
    /// travelling toward and the outgoing page exits the opposite way, so
    /// forward and back feel physically distinct. Collapses to a plain fade
    /// when Reduce Motion is on.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let exitEdge: Edge = transitionEdge == .trailing ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: transitionEdge).combined(with: .opacity),
            removal: .move(edge: exitEdge).combined(with: .opacity)
        )
    }

    // MARK: - Introduction

    private var introductionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: Spacing.xxl)

                Image("osglogo")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(maxWidth: 122, maxHeight: 35)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityHidden(true)

                Text(AppL10n.string("onboarding.experience.intro.eyebrow"))
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: 28)
                    .background(palette.surfaceElevated, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(palette.dividerStrong, lineWidth: 0.5)
                    }
                    .padding(.top, Spacing.hero)

                Text(AppL10n.string("onboarding.experience.intro.title"))
                    .font(TypeStyle.largeTitle)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, Spacing.md)

                Text(AppL10n.string("onboarding.experience.intro.subtitle"))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.sm)

                VStack(spacing: Spacing.sm) {
                    promiseRow(
                        icon: "waveform",
                        title: "onboarding.experience.promise.voice.title",
                        detail: "onboarding.experience.promise.voice.body"
                    )
                    promiseRow(
                        icon: "sparkles",
                        title: "onboarding.experience.promise.agent.title",
                        detail: "onboarding.experience.promise.agent.body"
                    )
                    promiseRow(
                        icon: "key",
                        title: "onboarding.experience.promise.privacy.title",
                        detail: "onboarding.experience.promise.privacy.body"
                    )
                }
                .padding(.top, Spacing.xxl)

                if let privacyURL = LegalLinks.privacyPolicyURL {
                    Link(destination: privacyURL) {
                        Text(AppL10n.string("legal.privacyPolicy"))
                            .font(TypeStyle.caption)
                            .foregroundStyle(palette.textSecondary)
                            .underline()
                    }
                    .padding(.top, Spacing.lg)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func promiseRow(
        icon: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 42, height: 42)
                .background(palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.medium))

            VStack(alignment: .leading, spacing: 3) {
                Text(AppL10n.string(title))
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                Text(AppL10n.string(detail))
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .cardElevation()
    }

    // MARK: - Permissions

    private var permissionsPage: some View {
        OnboardingExperienceShell(
            title: "onboarding.experience.permissions.title",
            subtitle: "onboarding.experience.permissions.subtitle",
            onBack: goBack
        ) {
            VStack(spacing: Spacing.sm) {
                permissionRow(
                    icon: "mic.fill",
                    title: "onboarding.permission.mic.title",
                    detail: "onboarding.permission.mic.body",
                    granted: micStatus == .granted,
                    denied: micStatus == .denied
                )
                permissionRow(
                    icon: "waveform.badge.mic",
                    title: "onboarding.permission.speech.title",
                    detail: "onboarding.permission.speech.body",
                    granted: speechStatus == .granted,
                    denied: speechPermissionDenied
                )
            }
            .padding(.top, Spacing.xxl)

            Text(AppL10n.string("onboarding.experience.permissions.systemHint"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            if !permissionsReady {
                Button(AppL10n.string("onboarding.experience.permissions.later")) {
                    goForward()
                }
                .font(TypeStyle.footnote.weight(.medium))
                .foregroundStyle(palette.accent)
                .padding(.top, Spacing.xl)
            }
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        denied: Bool
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(TypeStyle.title3)
                .foregroundStyle(palette.textPrimary)
                .frame(width: 42, height: 42)
                .background(palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.medium))

            VStack(alignment: .leading, spacing: 2) {
                Text(AppL10n.string(title))
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                Text(AppL10n.string(detail))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: granted ? "checkmark.circle.fill" : (denied ? "exclamationmark.circle.fill" : "circle"))
                .font(TypeStyle.title3)
                .foregroundStyle(granted ? palette.accent : (denied ? palette.warning : palette.textTertiary))
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .cardElevation()
    }

    // MARK: - Keyboard setup

    // MARK: - Keyboard setup and verification (single merged step)

    /// Adds the keyboard and verifies Full Access on one screen: the extension
    /// can only report Full Access by actually running, so the verify field
    /// lives here rather than on a separate switch step.
    private var keyboardPage: some View {
        OnboardingExperienceShell(
            title: "onboarding.experience.keyboard.title",
            subtitle: "onboarding.experience.keyboard.subtitle",
            onBack: goBack
        ) {
            KeyboardSettingsPreview(
                isKeyboardEnabled: keyboardInstalled == true,
                hasFullAccess: keyboardReady
            )
                .padding(.top, Spacing.xxl)

            HStack(spacing: Spacing.xs) {
                Image(systemName: keyboardReady ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(keyboardReady ? palette.accent : palette.textSecondary)
                Text(AppL10n.string(keyboardStatusHint))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Spacing.lg)

            if keyboardSettingsOpenFailed {
                Text(AppL10n.string("onboarding.experience.keyboard.openFailed"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.warning)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.lg)
            }

            keyboardVerifySection
                .padding(.top, Spacing.lg)

            if hasOpenedKeyboardSettings, !keyboardReady {
                Button {
                    openKeyboardSettings()
                } label: {
                    Label(
                        keyboardAppeared
                            ? "onboarding.experience.keyboardSwitch.checkSettings"
                            : "onboarding.experience.keyboard.openAgain",
                        systemImage: "arrow.up.right.square"
                    )
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        palette.surface,
                        in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, Spacing.md)
            }

            // The extension never reports back until it actually runs, so a
            // stalled verification must not trap the user in onboarding.
            if !keyboardReady, keyboardVerificationTimedOut, !keyboardAppeared {
                Button(AppL10n.string("onboarding.experience.keyboardSwitch.skip")) {
                    goToLoginReward()
                }
                .font(TypeStyle.footnote.weight(.medium))
                .foregroundStyle(palette.accent)
                .padding(.top, Spacing.sm)
            }

            resourceStatus
                .padding(.top, Spacing.md)
        }
        .onAppear {
            deployment.deployNow(reason: "onboarding.experience.keyboard")
        }
    }

    /// The type-to-verify block. Typing here launches the extension, which is
    /// the only way the host learns Full Access was granted.
    private var keyboardVerifySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(AppL10n.string("onboarding.experience.keyboardSwitch.instruction"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                AppL10n.string("onboarding.experience.keyboardSwitch.placeholder"),
                text: $keyboardSwitchText,
                axis: .vertical
            )
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .focused($keyboardSwitchFieldFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                palette.formSurface,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .accessibilityIdentifier("onboarding.keyboardSwitch.textField")

            HStack(spacing: Spacing.xs) {
                if keyboardReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                } else if keyboardAppeared || keyboardVerificationTimedOut {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(palette.warning)
                } else if hasOpenedKeyboardSettings {
                    ProgressView()
                        .tint(palette.accent)
                } else {
                    Image(systemName: "keyboard")
                        .foregroundStyle(palette.textTertiary)
                }

                Text(AppL10n.string(keyboardVerificationStatus))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    /// iOS reports whether the keyboard is enabled, but only the extension can
    /// confirm Full Access.
    private var keyboardStatusHint: String {
        if keyboardReady {
            return "onboarding.experience.keyboard.ready"
        }
        if keyboardInstalled == true {
            return "onboarding.experience.keyboard.addedNeedsFullAccess"
        }
        return "onboarding.experience.keyboard.fullAccess"
    }

    private var keyboardVerificationStatus: String {
        if keyboardReady {
            return "onboarding.experience.keyboardSwitch.ready"
        }
        if keyboardAppeared {
            return "onboarding.experience.keyboardSwitch.fullAccessMissing"
        }
        if keyboardVerificationTimedOut {
            return "onboarding.experience.keyboardSwitch.timeout"
        }
        return "onboarding.experience.keyboardSwitch.waiting"
    }

    @ViewBuilder
    private var resourceStatus: some View {
        switch deployment.status {
        case .deploying:
            Label(AppL10n.string("onboarding.enable.resources.preparing"), systemImage: "hourglass")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
        case .ready:
            EmptyView()
        case .failed:
            Button {
                deployment.deployNow(force: true, reason: "onboarding.experience.retry")
            } label: {
                Label(AppL10n.string("onboarding.enable.resources.retry"), systemImage: "arrow.clockwise")
                    .font(TypeStyle.caption)
            }
            .foregroundStyle(palette.warning)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Real keyboard practice

    private var practicePage: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                        .font(TypeStyle.headline)
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(AppL10n.string("common.back")))

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(AppL10n.string(practiceTitle))
                    .font(TypeStyle.title)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppL10n.string(practiceSubtitle))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            practiceContent
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)
                .frame(maxHeight: .infinity, alignment: .top)

            if managedPracticeReady, keyboardAppeared, !keyboardReady {
                Button {
                    openKeyboardSettings()
                } label: {
                    Label(
                        AppL10n.string("onboarding.experience.practice.fullAccessAction"),
                        systemImage: "arrow.up.right.square"
                    )
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.warning)
                }
                .buttonStyle(.plain)
                .padding(.bottom, Spacing.sm)
            }
        }
    }

    @ViewBuilder
    private var practiceContent: some View {
        if isPreviewMode {
            practiceFeatureContent
        } else if !config.hasAcknowledgedCloudSharing {
            VStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)

                Text(AppL10n.string("onboarding.experience.practice.cloudBody"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    config.hasAcknowledgedCloudSharing = true
                } label: {
                    Text(AppL10n.string("onboarding.experience.practice.cloudAction"))
                        .primaryButton()
                }
                .buttonStyle(.plain)
            }
            .practiceSetupCard(palette: palette)
        } else if isPreparingManagedPractice {
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(palette.accent)
                Text(AppL10n.string("onboarding.experience.practice.preparingCredits"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .practiceSetupCard(palette: palette)
        } else if managedPracticeFailed {
            VStack(spacing: Spacing.md) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.warning)
                Text(AppL10n.string("onboarding.experience.practice.creditsFailed"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AppL10n.string("onboarding.experience.practice.retry")) {
                    prepareManagedPractice()
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.accent)
                Button(AppL10n.string("onboarding.experience.practice.skip")) {
                    goToLoginReward()
                }
                .font(TypeStyle.footnote.weight(.medium))
                .foregroundStyle(palette.accent)
            }
            .practiceSetupCard(palette: palette)
        } else {
            practiceFeatureContent
        }
    }

    private var practiceFeatureContent: some View {
        VStack(spacing: Spacing.md) {
            if practiceFeature == .voiceInput {
                practiceVoiceSample
            } else if practiceFeature == .clipboardTranslate
                || practiceFeature == .clipboardReply {
                practiceClipboardSample
            } else if practiceFeature == .askAI {
                practiceAskAIPrompt
            }
            practiceEditor
            HStack(spacing: Spacing.xs) {
                if managedPracticeReady || isPreviewMode {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)
                }
                Text(AppL10n.string("onboarding.experience.practice.waiting"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Button(AppL10n.string("onboarding.experience.practice.skip")) {
                guard !isPreviewMode else { return }
                goToLoginReward()
            }
            .font(TypeStyle.caption.weight(.medium))
            .foregroundStyle(palette.accent)
        }
    }

    @ViewBuilder
    private var accountOperationError: some View {
        if let key = accountSession.operationErrorKey {
            Text(AppL10n.string(key))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.warning)
                .multilineTextAlignment(.center)
        }
    }

    private var practiceEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: practiceFeature.editorSystemImage)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityHidden(true)
                Text(AppL10n.string(practiceFeature.progressKey))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 42)

            Divider().overlay(palette.divider)

            TextEditor(text: $practiceText)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($practiceFieldFocused)
                .padding(Spacing.sm)
                .accessibilityIdentifier("onboarding.practice.textEditor")
        }
        .frame(maxWidth: .infinity, minHeight: 172, maxHeight: 240)
        .background(palette.formSurface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .cardElevation()
    }

    private var practiceVoiceSample: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(AppL10n.string("onboarding.experience.practice.readAloud"))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)

            Text(AppL10n.string("onboarding.experience.practice.voiceSample"))
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: Radius.large))
        .accessibilityIdentifier("onboarding.practice.voiceSample")
    }

    private var practiceClipboardSample: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(AppL10n.string(practiceClipboardSampleLocalizationKey))
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                copyPracticeSample()
            } label: {
                Label {
                    Text(
                        didCopyPracticeSample
                            ? "onboarding.experience.practice.copied"
                            : "onboarding.experience.practice.copyAction"
                    )
                } icon: {
                    Image(
                        systemName: didCopyPracticeSample
                            ? "checkmark.circle.fill"
                            : "doc.on.doc"
                    )
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(didCopyPracticeSample ? palette.accent : palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    didCopyPracticeSample ? palette.accentMuted : palette.surfaceElevated,
                    in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.practice.copySample")
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .cardElevation()
    }

    private var practiceAskAIPrompt: some View {
        Text(AppL10n.string("onboarding.experience.practice.askAIPrompt"))
            .font(TypeStyle.bodyEmph)
            .foregroundStyle(palette.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: Radius.large))
    }

    private var practiceClipboardSampleLocalizationKey: String {
        practiceFeature == .clipboardTranslate
            ? "onboarding.experience.practice.translateSample"
            : "onboarding.experience.practice.replySample"
    }

    private var practiceTitle: String {
        if isPreviewMode {
            return practiceFeature.titleKey
        }
        if !permissionsReady {
            return "onboarding.experience.practice.permissionsTitle"
        }
        if !config.hasAcknowledgedCloudSharing {
            return "onboarding.experience.practice.cloudTitle"
        }
        if isPreparingManagedPractice || managedPracticeFailed {
            return "onboarding.experience.practice.creditsTitle"
        }
        if !keyboardAppeared {
            return "onboarding.experience.practice.switchTitle"
        }
        if !keyboardReady {
            return "onboarding.experience.practice.fullAccessTitle"
        }
        return practiceFeature.titleKey
    }

    private var practiceSubtitle: String {
        if isPreviewMode {
            return practiceFeature.subtitleKey
        }
        if !permissionsReady {
            return "onboarding.experience.practice.permissionsSubtitle"
        }
        if !config.hasAcknowledgedCloudSharing {
            return "onboarding.experience.practice.cloudSubtitle"
        }
        if isPreparingManagedPractice || managedPracticeFailed {
            return "onboarding.experience.practice.creditsSubtitle"
        }
        if !keyboardAppeared {
            return "onboarding.experience.practice.switchSubtitle"
        }
        if !keyboardReady {
            return "onboarding.experience.practice.fullAccessSubtitle"
        }
        return practiceFeature.subtitleKey
    }

    // MARK: - Optional account reward

    private var loginRewardPage: some View {
        OnboardingExperienceShell(
            title: "onboarding.experience.login.title",
            subtitle: "onboarding.experience.login.subtitle",
            onBack: goBack
        ) {
            VStack(spacing: Spacing.lg) {
                Image(systemName: "gift.circle")
                    .font(.system(size: 50, weight: .ultraLight))
                    .foregroundStyle(palette.textPrimary)
                    .symbolEffect(
                        .drawOn,
                        isActive: !reduceMotion && !showsLoginRewardIcon
                    )
                    .symbolEffectsRemoved(reduceMotion)
                    .accessibilityHidden(true)

                Text(
                    accountSession.isSignedIn
                        ? "onboarding.experience.login.signedIn"
                        : "onboarding.experience.login.body"
                )
                .font(TypeStyle.body)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                if accountSession.isSignedIn {
                    if let balance = loginRewardBalance {
                        Text(AppL10n.format("onboarding.experience.login.balance %lld", balance))
                            .font(TypeStyle.title)
                            .foregroundStyle(palette.textPrimary)
                    } else {
                        ProgressView()
                            .tint(palette.accent)
                    }
                } else {
                    AccountAppleAuthorizationButton(
                        purpose: .signIn,
                        onSignedIn: {
                            didRefreshLoginReward = false
                            refreshLoginRewardIfNeeded()
                        }
                    )
                    .disabled(accountSession.operation != nil)

                    accountOperationError
                }

                Button(AppL10n.string("onboarding.experience.login.skip")) {
                    goToComplete()
                }
                .font(TypeStyle.footnote.weight(.medium))
                .foregroundStyle(palette.accent)
                .opacity(accountSession.isSignedIn ? 0 : 1)
                .disabled(accountSession.isSignedIn || accountSession.operation != nil)
                .accessibilityHidden(accountSession.isSignedIn)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            )
            .cardElevation()
            .padding(.top, Spacing.xxl)
            .accessibilityIdentifier("onboarding.loginReward.card")
        }
        .task {
            guard !reduceMotion else { return }
            showsLoginRewardIcon = false
            do {
                // 等待页面首帧完成后，仅播放一次礼物图标绘制动画。
                try await Task.sleep(for: .milliseconds(120))
                showsLoginRewardIcon = true
            } catch {
                showsLoginRewardIcon = false
            }
        }
        .onDisappear {
            showsLoginRewardIcon = false
        }
    }

    private var loginRewardBalance: Int64? {
        guard case let .loaded(snapshot) = accountSession.snapshotPhase else {
            return nil
        }
        return snapshot.credits.balance
    }

    // MARK: - Complete

    private var completePage: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: Spacing.xxl)

                Image(systemName: "checkmark.circle")
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundStyle(palette.textPrimary)
                    .symbolEffect(
                        .drawOn,
                        isActive: !reduceMotion && !showsCompleteIcon
                    )
                    .symbolEffectsRemoved(reduceMotion)
                    .frame(width: 108, height: 108)

                Text(
                    completedAllPracticeFeatures
                        ? "onboarding.experience.complete.verifiedTitle"
                        : "onboarding.experience.complete.title"
                )
                .font(TypeStyle.largeTitle)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.xxl)

                Text(AppL10n.string("onboarding.experience.complete.subtitle"))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.sm)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: Spacing.xs),
                        GridItem(.flexible(), spacing: Spacing.xs)
                    ],
                    spacing: Spacing.xs
                ) {
                    capability("mic.fill", "onboarding.experience.complete.dictate")
                    capability("sparkles", "onboarding.experience.complete.agent")
                    capability("translate", "onboarding.experience.complete.translate")
                    capability("arrowshape.turn.up.left.fill", "onboarding.experience.complete.reply")
                }
                .padding(.top, Spacing.xxl)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .task {
            guard !reduceMotion else { return }
            showsCompleteIcon = false
            do {
                // 完成页每次进入时只绘制一次主图标。
                try await Task.sleep(for: .milliseconds(120))
                showsCompleteIcon = true
            } catch {
                showsCompleteIcon = false
            }
        }
        .onDisappear {
            showsCompleteIcon = false
        }
    }

    private func capability(_ icon: String, _ title: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(AppL10n.string(title))
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(1.42, contentMode: .fit)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large))
        .cardElevation()
    }

    // MARK: - Bottom action

    private var bottomAction: some View {
        Button(action: performPrimaryAction) {
            HStack(spacing: Spacing.xs) {
                if isRequestingPermissions
                    || (currentStep == .keyboard
                && hasOpenedKeyboardSettings
                && !keyboardSwitchCanContinue) {
                    ProgressView()
                        .tint(palette.textOnAccent)
                }
                Text(AppL10n.string(primaryActionTitle))
            }
            .primaryButton()
        }
        .buttonStyle(.plain)
        .disabled(primaryActionDisabled)
        .opacity(primaryActionDisabled ? 0.55 : 1)
    }

    private var primaryActionDisabled: Bool {
        if previewsAllScreens {
            return false
        }
        if isRequestingPermissions
            || (currentStep == .keyboard
                && hasOpenedKeyboardSettings
                && !keyboardSwitchCanContinue) {
            return true
        }
        if currentStep == .practice {
            return !completedAllPracticeFeatures
        }
        if currentStep == .loginReward, accountSession.isSignedIn {
            return loginRewardBalance == nil
        }
        return false
    }

    private var primaryActionTitle: String {
        switch currentStep {
        case .introduction:
            return "onboarding.experience.intro.action"
        case .permissions:
            if permissionsReady { return "common.continue" }
            if micStatus == .denied || speechPermissionDenied {
                return "onboarding.permission.openSettings"
            }
            return "common.continue"
        case .keyboard, .keyboardSwitch:
            if keyboardReady { return "common.continue" }
            if keyboardAppeared {
                return "onboarding.experience.keyboardSwitch.continueWithoutFullAccess"
            }
            if !hasOpenedKeyboardSettings {
                return "onboarding.enable.openSettings"
            }
            return "onboarding.experience.keyboardSwitch.waitingAction"
        case .practice:
            return "common.continue"
        case .loginReward:
            return accountSession.isSignedIn
                ? "common.continue"
                : "onboarding.experience.login.skip"
        case .complete:
            return "onboarding.experience.complete.action"
        }
    }

    private func performPrimaryAction() {
        if advancePreviewIfNeeded() {
            return
        }
        switch currentStep {
        case .introduction:
            goForward()
        case .permissions:
            handlePermissionAction()
        case .keyboard, .keyboardSwitch:
            if keyboardSwitchCanContinue {
                goForward()
            } else if !hasOpenedKeyboardSettings {
                openKeyboardSettings()
            }
            // Otherwise verification is still in flight — wait for the monitor.
        case .practice:
            guard completedAllPracticeFeatures else { return }
            goToLoginReward()
        case .loginReward:
            goToComplete()
        case .complete:
            finishOnboarding()
        }
    }

    private func advancePreviewIfNeeded() -> Bool {
        #if DEBUG
        guard previewsAllScreens else { return false }
        guard previewPageIndex < Self.allPreviewDestinations.count - 1 else {
            return true
        }
        transitionEdge = .trailing
        withAnimation(Motion.soft) {
            previewPageIndex += 1
            if case let .practice(feature) = activePreviewDestination {
                practiceFeature = feature
                practiceText = ""
                didCopyPracticeSample = false
            }
        }
        return true
        #else
        return false
        #endif
    }

    // MARK: - State and actions

    private var permissionsReady: Bool {
        micStatus == .granted && speechStatus == .granted
    }

    /// Full Access is required for the practice steps, but the keyboard itself
    /// already works without it. Once the extension has reported an appearance
    /// the switch is verified, so onboarding must not block on Full Access.
    private var keyboardSwitchCanContinue: Bool {
        keyboardReady || keyboardAppeared
    }

    private var speechPermissionDenied: Bool {
        speechStatus == .denied || speechStatus == .restricted
    }

    private func handlePermissionAction() {
        if micStatus == .denied || speechPermissionDenied {
            AppPermissions.openSystemSettings()
            return
        }
        if permissionsReady {
            goForward()
            return
        }

        isRequestingPermissions = true
        Task { @MainActor in
            await AppPermissions.requestFlowPermissionsIfNeeded()
            refreshState()
            isRequestingPermissions = false
            if permissionsReady {
                goForward()
            }
        }
    }

    /// Settings can refuse the jump outright, and the public fallback only
    /// reaches the app's own page. Mark the step optimistically so returning
    /// from Settings still advances, and surface the written path when iOS
    /// refuses every attempt.
    private func openKeyboardSettings() {
        hasOpenedKeyboardSettings = true
        keyboardSettingsOpenFailed = false
        Task { @MainActor in
            await ensureSettingsEntryExists()
            AppPermissions.openKeyboardSettings { opened in
                guard !opened else { return }
                Task { @MainActor in
                    hasOpenedKeyboardSettings = false
                    keyboardSettingsOpenFailed = true
                }
            }
        }
    }

    /// The public settings URL resolves to the app's own page only once the
    /// app *has* one, and iOS creates that page the first time the app asks
    /// for a permission. A user who chose "set up later" has never asked, so
    /// the fallback would land on the Settings root. Requesting once here —
    /// the outcome does not matter, only that it was asked — gives the
    /// fallback somewhere to land.
    @MainActor
    private func ensureSettingsEntryExists() async {
        guard micStatus == .undetermined, speechStatus == .undetermined else { return }
        _ = await AppPermissions.requestMicrophone()
        refreshState()
    }

    private func beginPracticeIfNeeded() {
        if practiceStartedAt == nil {
            beginPractice()
        } else if managedPracticeReady, permissionsReady {
            flowManager.activateOnForeground(reason: "onboarding.practice.resume")
            focusPracticeField()
        } else if config.hasAcknowledgedCloudSharing {
            prepareManagedPractice()
        }
    }

    private func beginPractice() {
        refreshState()
        practiceStartedAt = nil
        completedPracticeFeatures = loadCompletedPracticeFeatures()
        practiceFeature = firstIncompletePracticeFeature ?? .askAI
        practiceText = ""
        practiceSessionID = nil
        didCopyPracticeSample = false
        managedPracticeReady = false
        managedPracticeFailed = false
        KeyboardSetupBridge.setOnboardingPracticeActive(false)
        if completedAllPracticeFeatures {
            goToLoginReward()
        } else if config.hasAcknowledgedCloudSharing {
            prepareManagedPractice()
        }
    }

    private func prepareManagedPractice() {
        guard currentStep == .practice,
              config.hasAcknowledgedCloudSharing,
              !isPreparingManagedPractice else { return }
        isPreparingManagedPractice = true
        managedPracticeFailed = false
        managedPracticeReady = false
        KeyboardSetupBridge.setOnboardingPracticeActive(false)

        // OOBE keeps audio on-device. Only the transcript is sent to the
        // managed polish gateway, where the request is tagged and audited.
        config.engineMode = "local"
        config.modeId = "polish"

        Task { @MainActor in
            let session: OOBEPracticeSession
            do {
                session = try await oobeClient.beginPractice(feature: practiceFeature)
            } catch {
                guard currentStep == .practice else { return }
                isPreparingManagedPractice = false
                managedPracticeFailed = true
                return
            }
            guard currentStep == .practice else { return }
            isPreparingManagedPractice = false
            config.credentialSource = .managed
            managedPracticeReady = true
            practiceStartedAt = Date()
            practiceSessionID = session.sessionID
            if permissionsReady {
                flowManager.activateOnForeground(reason: "onboarding.practice.managed")
            }
            focusPracticeField()
        }
    }

    private func focusKeyboardSwitchField() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            // Only steal focus (and raise the system keyboard) once the user has
            // been to Settings — before that the setup preview must stay visible.
            guard currentStep == .keyboard,
                  !keyboardReady,
                  hasOpenedKeyboardSettings else { return }
            keyboardSwitchFieldFocused = true
        }
    }

    private func focusPracticeField() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard currentStep == .practice else { return }
            practiceFieldFocused = true
        }
    }

    private func endPractice() {
        practiceFieldFocused = false
        isPreparingManagedPractice = false
        managedPracticeReady = false
        practiceSessionID = nil
        KeyboardSetupBridge.setOnboardingPracticeActive(false)
        Task {
            await oobeClient.endPractice()
        }
    }

    @MainActor
    private func monitorKeyboardVerification() async {
        let startedAt = Date()
        refreshState()
        focusKeyboardSwitchField()

        while !Task.isCancelled, currentStep == .keyboard {
            refreshState()
            if keyboardReady {
                keyboardVerificationTimedOut = false
                keyboardSwitchFieldFocused = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Auto-advance once Full Access is verified, matching the
                // practice steps — no manual Continue tap needed.
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, currentStep == .keyboard else { return }
                goForward()
                return
            }
            if !keyboardVerificationTimedOut,
               Date().timeIntervalSince(startedAt) >= 12 {
                keyboardVerificationTimedOut = true
            }
            try? await Task.sleep(for: .milliseconds(350))
        }
    }

    @MainActor
    private func monitorPractice() async {
        while !Task.isCancelled, currentStep == .practice {
            refreshState()
            if let sessionID = practiceSessionID,
               KeyboardSetupBridge.oobePracticeCompletion(
                   sessionID: sessionID,
                   feature: practiceFeature
               ) != nil {
                let completedFeature = practiceFeature
                completedPracticeFeatures.insert(completedFeature)
                persistCompletedPracticeFeatures()
                // The reply step demonstrates auto mode (the keyboard drafts a
                // reply on its own). Persist that behavior so it keeps working
                // after onboarding — auto mode also requires clipboard history.
                if completedFeature == .clipboardReply {
                    if !config.clipboardHistoryEnabled {
                        config.clipboardHistoryEnabled = true
                    }
                    if !config.clipboardAutoModeEnabled {
                        config.clipboardAutoModeEnabled = true
                    }
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, currentStep == .practice else { return }
                if let next = completedFeature.next {
                    advancePractice(to: next)
                } else {
                    goToLoginReward()
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(350))
        }
    }

    private func advancePractice(to feature: ManagedGatewayOOBEFeature) {
        guard let sessionID = practiceSessionID,
              KeyboardSetupBridge.updateOOBEExpectedFeature(
                  feature,
                  sessionID: sessionID
              ) != nil else {
            managedPracticeReady = false
            managedPracticeFailed = true
            return
        }
        withAnimation(Motion.soft) {
            practiceFeature = feature
            practiceText = ""
            didCopyPracticeSample = false
        }
        focusPracticeField()
    }

    private func copyPracticeSample() {
        let sample = AppL10n.string(
            practiceClipboardSampleLocalizationKey,
            language: previewLanguageOverride
        )
        if isPreviewMode {
            UIPasteboard.general.string = sample
            didCopyPracticeSample = true
            return
        }
        guard let sessionID = practiceSessionID else { return }
        guard KeyboardSetupBridge.seedOOBEClipboardMaterial(
            sample,
            sessionID: sessionID
        ) != nil else {
            managedPracticeFailed = true
            return
        }
        // This is a direct response to the user's button tap. The keyboard
        // still reads only the session-bound sample from App Group storage.
        UIPasteboard.general.string = sample
        didCopyPracticeSample = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        focusPracticeField()
    }

    private var completedAllPracticeFeatures: Bool {
        Set(ManagedGatewayOOBEFeature.allCases).isSubset(of: completedPracticeFeatures)
    }

    private var firstIncompletePracticeFeature: ManagedGatewayOOBEFeature? {
        ManagedGatewayOOBEFeature.allCases.first {
            !completedPracticeFeatures.contains($0)
        }
    }

    private func loadCompletedPracticeFeatures() -> Set<ManagedGatewayOOBEFeature> {
        let values = UserDefaults.standard.stringArray(
            forKey: Self.completedPracticeFeaturesKey
        ) ?? []
        return Set(values.compactMap(ManagedGatewayOOBEFeature.init(rawValue:)))
    }

    private func persistCompletedPracticeFeatures() {
        UserDefaults.standard.set(
            completedPracticeFeatures.map(\.rawValue).sorted(),
            forKey: Self.completedPracticeFeaturesKey
        )
    }

    private func refreshLoginRewardIfNeeded() {
        guard currentStep == .loginReward,
              accountSession.isSignedIn,
              !didRefreshLoginReward else { return }
        didRefreshLoginReward = true
        Task { @MainActor in
            await oobeClient.endPractice()
            if await accountSession.prepareManagedGateway() {
                config.credentialSource = .managed
            }
            await accountSession.refreshAccountData(force: true)
        }
    }

    private func refreshState() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
        // iOS reports the enabled-keyboard list to the host, so a removed
        // keyboard can override the extension's older self-report. It cannot
        // confirm Full Access — only the extension can — so `nil`/`true` leave
        // the bridge's own answer untouched.
        let installed = KeyboardInstallationProbe.isKeyboardEnabled()
        keyboardInstalled = installed
        keyboardAppeared = KeyboardSetupBridge.hasAppeared && installed != false
        keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip && installed != false
    }

    private func goForward() {
        let next: OnboardingExperienceStep
        switch currentStep {
        case .introduction:
            next = .permissions
        case .permissions:
            next = .keyboard
        case .keyboard, .keyboardSwitch:
            next = .practice
        case .practice:
            next = .loginReward
        case .loginReward, .complete:
            next = .complete
        }
        if next == .practice {
            resetPracticeRun()
        }
        transitionEdge = .trailing
        withAnimation(Motion.soft) {
            config.onboardingPage = next.rawValue
        }
    }

    private func goBack() {
        let previous: OnboardingExperienceStep
        switch currentStep {
        case .introduction, .permissions:
            previous = .introduction
        case .keyboard, .keyboardSwitch:
            previous = .permissions
        case .practice:
            previous = .keyboard
        case .loginReward:
            previous = .practice
        case .complete:
            previous = .loginReward
        }
        if previous == .practice {
            resetPracticeRun()
        }
        transitionEdge = .leading
        withAnimation(Motion.soft) {
            config.onboardingPage = previous.rawValue
        }
    }

    private func goToComplete() {
        config.engineMode = "local"
        if !accountSession.isSignedIn {
            // Skipping the optional account offer leaves a fully usable local
            // voice keyboard instead of a managed mode with no credential.
            config.credentialSource = .byok
        }
        transitionEdge = .trailing
        withAnimation(Motion.soft) {
            config.onboardingPage = OnboardingExperienceStep.complete.rawValue
        }
    }

    private func goToLoginReward() {
        endPractice()
        transitionEdge = .trailing
        withAnimation(Motion.soft) {
            config.onboardingPage = OnboardingExperienceStep.loginReward.rawValue
        }
    }

    private func finishOnboarding() {
        endPractice()
        UserDefaults.standard.removeObject(forKey: Self.completedPracticeFeaturesKey)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            config.hasCompletedOnboarding = true
        }
    }

    private func resetPracticeRun() {
        UserDefaults.standard.removeObject(forKey: Self.completedPracticeFeaturesKey)
        completedPracticeFeatures.removeAll()
        practiceFeature = .voiceInput
        practiceText = ""
        practiceStartedAt = nil
        didCopyPracticeSample = false
    }

    private func applyPrivacySafeDefaultsIfNeeded() {
        guard !config.hasCompletedOnboarding, config.onboardingPage == 0 else { return }
        // First-run voice should work without asking users to understand an
        // ASR provider or supply a cloud key.
        if config.apiKey.isEmpty, config.engineMode == "cloud" {
            config.engineMode = "local"
        }
    }

    private func migrateLegacyProgressIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationKey) else {
            if OnboardingExperienceStep(rawValue: config.onboardingPage) == nil {
                config.onboardingPage = 0
            }
            return
        }

        if !config.hasCompletedOnboarding {
            switch config.onboardingPage {
            case 1, 2:
                config.onboardingPage = OnboardingExperienceStep.permissions.rawValue
            case 3:
                config.onboardingPage = OnboardingExperienceStep.keyboard.rawValue
            case 4, 5:
                config.onboardingPage = OnboardingExperienceStep.introduction.rawValue
            default:
                config.onboardingPage = OnboardingExperienceStep.introduction.rawValue
            }
        }
        defaults.set(true, forKey: Self.migrationKey)
    }
}

#if DEBUG
@MainActor
struct OOBEPreviewHarness: View {
    @ObservedObject private var config = ProviderConfig.shared
    @StateObject private var flowManager = FlowSessionManager()
    @StateObject private var accountSession: AccountSessionCoordinator

    init() {
        _accountSession = StateObject(
            wrappedValue: AccountSessionCoordinator(
                dependencies: LiveAccountDependencyFactory.make()
            )
        )
    }

    var body: some View {
        ThemedRoot {
            OnboardingExperienceView(config: config)
                .environmentObject(flowManager)
                .environmentObject(accountSession)
        }
        .environment(\.locale, OnboardingExperienceView.previewLanguage.swiftUILocale)
    }
}
#endif

private extension View {
    func practiceSetupCard(palette: ThemePalette) -> some View {
        frame(maxWidth: .infinity, minHeight: 172)
            .padding(Spacing.lg)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .cardElevation()
    }
}

/// Ambient backdrop for the onboarding flow: the original calm top wash plus a
/// pair of soft, slowly drifting accent orbs that give the emptier screens
/// (intro, complete) a sense of life without competing with the content. The
/// orbs are heavily blurred and low-opacity so they read as light, not shapes,
/// and they hold still entirely when Reduce Motion is on.
private struct OnboardingAmbientBackground: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [
                        palette.accent.opacity(0.10),
                        palette.accent.opacity(0.025),
                        palette.background.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: size.height * 0.46)

                orb(diameter: size.width * 0.95, opacity: 0.20)
                    .position(
                        x: size.width * (drift ? 0.16 : 0.26),
                        y: size.height * (drift ? 0.14 : 0.09)
                    )

                orb(diameter: size.width * 0.75, opacity: 0.13)
                    .position(
                        x: size.width * (drift ? 0.88 : 0.80),
                        y: size.height * (drift ? 0.24 : 0.32)
                    )
            }
            .frame(width: size.width, height: size.height, alignment: .top)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func orb(diameter: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(palette.accent.opacity(opacity))
            .frame(width: diameter, height: diameter)
            .blur(radius: diameter * 0.34)
    }
}

private struct OnboardingExperienceShell<Content: View>: View {
    @Environment(\.themePalette) private var palette

    let title: String
    let subtitle: String
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(TypeStyle.headline)
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(AppL10n.string("common.back")))
                    Spacer()
                }

                VStack(spacing: Spacing.sm) {
                    Text(AppL10n.string(title))
                        .font(TypeStyle.largeTitle)
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string(subtitle))
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.xl)

                content

                Spacer(minLength: Spacing.xl)
            }
            .padding(.horizontal, Spacing.xl)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// Mirrors the two switches the user has to find in Settings. They are shown
/// separately because they are separate steps — enabling the keyboard does not
/// grant Full Access — and because each is verified by a different mechanism.
private struct KeyboardSettingsPreview: View {
    @Environment(\.themePalette) private var palette

    let isKeyboardEnabled: Bool
    let hasFullAccess: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(AppL10n.string("onboarding.experience.keyboard.previewTitle"))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 42)

            Divider().overlay(palette.divider)

            row(title: "OSGKeyboard", isOn: isKeyboardEnabled, showsBrandMark: true)

            Divider().overlay(palette.divider).padding(.leading, Spacing.md)

            row(
                title: AppL10n.string("onboarding.experience.keyboard.fullAccessRow"),
                isOn: hasFullAccess,
                showsBrandMark: false
            )
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .cardElevation()
    }

    private func row(title: String, isOn: Bool, showsBrandMark: Bool) -> some View {
        HStack(spacing: Spacing.md) {
            if showsBrandMark {
                Image("OSGBrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
            } else {
                Color.clear.frame(width: 28, height: 28)
            }

            Text(title)
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.textPrimary)

            Spacer()

            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? palette.accent : palette.surfaceElevated)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(isOn ? palette.textOnAccent : palette.textTertiary)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
            .animation(Motion.quick, value: isOn)
        }
        .padding(Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "1" : "0"))
    }
}
