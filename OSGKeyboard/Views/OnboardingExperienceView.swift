// OnboardingExperienceView.swift
// OSGKeyboard · Main App
//
// A short, outcome-led first run:
//   1) Explain the product and its data boundaries.
//   2) Request the two permissions needed by Flow.
//   3) Guide keyboard installation with a visual system-settings preview.
//   4) Activate and verify the real keyboard in a host text field.
//   5) Teach four real features without requiring an account or API key.
//   6) Offer optional sign-in for the existing signup reward.
//   7) Celebrate the verified onboarding outcomes.

import OSGKeyboardShared
import SwiftUI
import UIKit

private enum OnboardingExperienceStep: Int, CaseIterable {
    case introduction = 0
    case permissions = 1
    case keyboard = 2
    // Keep existing persisted raw values stable while inserting this step
    // between keyboard setup and practice.
    case keyboardSwitch = 5
    case practice = 3
    case complete = 4
    // Appended so all existing persisted values keep their original meaning.
    case loginReward = 6
}

private extension ManagedGatewayOOBEFeature {
    var progressKey: LocalizedStringKey {
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

    var titleKey: LocalizedStringKey {
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

    var subtitleKey: LocalizedStringKey {
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

struct OnboardingExperienceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var flowManager: FlowSessionManager
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @ObservedObject var config: ProviderConfig
    @ObservedObject private var deployment = RimeDeploymentController.shared
    private let oobeClient = OOBEClientInfrastructure.shared

    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var keyboardAppeared = KeyboardSetupBridge.hasAppeared
    @State private var keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    @State private var hasOpenedKeyboardSettings = false
    @State private var isRequestingPermissions = false
    @State private var keyboardSwitchText = ""
    @State private var keyboardVerificationTimedOut = false
    @State private var practiceText = ""
    @State private var practiceStartedAt: Date?
    @State private var isPreparingManagedPractice = false
    @State private var managedPracticeReady = false
    @State private var managedPracticeFailed = false
    @State private var practiceFeature: ManagedGatewayOOBEFeature = .voiceInput
    @State private var practiceSessionID: UUID?
    @State private var completedPracticeFeatures: Set<ManagedGatewayOOBEFeature> = []
    @State private var didCopyPracticeSample = false
    @State private var didRefreshLoginReward = false
    @FocusState private var keyboardSwitchFieldFocused: Bool
    @FocusState private var practiceFieldFocused: Bool

    private static let migrationKey = "onboarding.experience.v2.migrated"
    private static let completedPracticeFeaturesKey =
        "onboarding.experience.oobe.completedFeatures.v1"

    private var currentStep: OnboardingExperienceStep {
        OnboardingExperienceStep(rawValue: config.onboardingPage) ?? .introduction
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ambientBackground

            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(currentStep)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                bottomAction
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .onAppear {
            migrateLegacyProgressIfNeeded()
            applyPrivacySafeDefaultsIfNeeded()
            refreshState()
            if currentStep == .practice {
                beginPractice()
            } else if currentStep == .loginReward {
                refreshLoginRewardIfNeeded()
            }
        }
        .onDisappear {
            endPractice()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshState()
            if currentStep == .keyboard, hasOpenedKeyboardSettings {
                goForward()
                return
            }
            if currentStep == .keyboardSwitch, !keyboardReady {
                focusKeyboardSwitchField()
            }
            if currentStep == .practice {
                beginPracticeIfNeeded()
            }
        }
        .onChange(of: currentStep) { previous, current in
            if previous == .keyboardSwitch {
                keyboardSwitchFieldFocused = false
            }
            if previous == .practice {
                endPractice()
            }
            if current == .keyboardSwitch {
                keyboardVerificationTimedOut = false
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
            guard isSignedIn, currentStep == .loginReward else { return }
            didRefreshLoginReward = false
            refreshLoginRewardIfNeeded()
        }
        .onChange(of: config.hasAcknowledgedCloudSharing) { _, acknowledged in
            guard acknowledged, currentStep == .practice else { return }
            prepareManagedPractice()
        }
        .task(id: currentStep) {
            switch currentStep {
            case .keyboardSwitch:
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
        case .keyboard:
            keyboardPage
        case .keyboardSwitch:
            keyboardSwitchPage
        case .practice:
            practicePage
        case .loginReward:
            loginRewardPage
        case .complete:
            completePage
        }
    }

    private var ambientBackground: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [
                    palette.accent.opacity(0.10),
                    palette.accent.opacity(0.025),
                    palette.background.opacity(0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: geometry.size.height * 0.46)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: - Introduction

    private var introductionPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: Spacing.xxl)

                Image("osglogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 174, maxHeight: 50)
                    .accessibilityHidden(true)

                Text("onboarding.experience.intro.eyebrow")
                    .font(TypeStyle.caption)
                    .tracking(1.2)
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: 28)
                    .background(palette.accentMuted, in: Capsule())
                    .padding(.top, Spacing.hero)

                Text("onboarding.experience.intro.title")
                    .font(TypeStyle.largeTitle)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, Spacing.md)

                Text("onboarding.experience.intro.subtitle")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.sm)

                VStack(spacing: Spacing.sm) {
                    promiseRow(
                        icon: "waveform",
                        title: "onboarding.experience.privacy.local.title",
                        detail: "onboarding.experience.privacy.local.body"
                    )
                    promiseRow(
                        icon: "network",
                        title: "onboarding.experience.privacy.cloud.title",
                        detail: "onboarding.experience.privacy.cloud.body"
                    )
                    promiseRow(
                        icon: "keyboard",
                        title: "onboarding.experience.privacy.anywhere.title",
                        detail: "onboarding.experience.privacy.anywhere.body"
                    )
                }
                .padding(.top, Spacing.xxl)

                if let privacyURL = LegalLinks.privacyPolicyURL {
                    Link(destination: privacyURL) {
                        Text("legal.privacyPolicy")
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
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 42, height: 42)
                .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: Radius.medium))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
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

            Text("onboarding.experience.permissions.systemHint")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)

            if !permissionsReady {
                Button("onboarding.experience.permissions.later") {
                    goForward()
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Spacing.xl)
            }
        }
    }

    private func permissionRow(
        icon: String,
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        granted: Bool,
        denied: Bool
    ) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 42, height: 42)
                .background(palette.accentMuted, in: RoundedRectangle(cornerRadius: Radius.medium))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: Spacing.sm)

            Image(systemName: granted ? "checkmark.circle.fill" : (denied ? "exclamationmark.circle.fill" : "circle"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(granted ? palette.accent : (denied ? palette.warning : palette.textTertiary))
                .accessibilityHidden(true)
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Keyboard setup

    private var keyboardPage: some View {
        OnboardingExperienceShell(
            title: "onboarding.experience.keyboard.title",
            subtitle: "onboarding.experience.keyboard.subtitle",
            onBack: goBack
        ) {
            KeyboardSettingsPreview(isReady: keyboardReady)
                .padding(.top, Spacing.xxl)

            HStack(spacing: Spacing.xs) {
                Image(systemName: keyboardReady ? "checkmark.circle.fill" : "info.circle")
                    .foregroundStyle(keyboardReady ? palette.accent : palette.textSecondary)
                Text(
                    keyboardReady
                        ? "onboarding.experience.keyboard.ready"
                        : "onboarding.experience.keyboard.fullAccess"
                )
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Spacing.lg)

            if hasOpenedKeyboardSettings, !keyboardReady {
                Button("onboarding.experience.keyboard.openAgain") {
                    openKeyboardSettings()
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Spacing.lg)
            }

            resourceStatus
                .padding(.top, Spacing.md)
        }
        .onAppear {
            deployment.deployNow(reason: "onboarding.experience.keyboard")
        }
    }

    // MARK: - Keyboard activation and verification

    private var keyboardSwitchPage: some View {
        OnboardingExperienceShell(
            title: "onboarding.experience.keyboardSwitch.title",
            subtitle: "onboarding.experience.keyboardSwitch.subtitle",
            onBack: goBack
        ) {
            VStack(spacing: Spacing.md) {
                Image(systemName: "globe")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)

                Text("onboarding.experience.keyboardSwitch.instruction")
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
            .padding(.top, Spacing.xxl)

            TextField(
                "onboarding.experience.keyboardSwitch.placeholder",
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
                palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(
                        keyboardReady ? palette.accent : palette.dividerStrong,
                        lineWidth: keyboardReady ? 1.5 : 0.5
                    )
            )
            .accessibilityIdentifier("onboarding.keyboardSwitch.textField")
            .padding(.top, Spacing.lg)

            HStack(spacing: Spacing.xs) {
                if keyboardReady {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                } else if keyboardAppeared || keyboardVerificationTimedOut {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(palette.warning)
                } else {
                    ProgressView()
                        .tint(palette.accent)
                }

                Text(keyboardVerificationStatus)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, Spacing.md)

            if !keyboardReady, keyboardAppeared || keyboardVerificationTimedOut {
                Button("onboarding.experience.keyboardSwitch.checkSettings") {
                    openKeyboardSettings()
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.accent)
                .padding(.top, Spacing.sm)
            }
        }
    }

    private var keyboardVerificationStatus: LocalizedStringKey {
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
            Label("onboarding.enable.resources.preparing", systemImage: "hourglass")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
        case .ready:
            EmptyView()
        case .failed:
            Button {
                deployment.deployNow(force: true, reason: "onboarding.experience.retry")
            } label: {
                Label("onboarding.enable.resources.retry", systemImage: "arrow.clockwise")
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.back"))

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(practiceTitle)
                    .font(TypeStyle.title)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(practiceSubtitle)
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
                        "onboarding.experience.practice.fullAccessAction",
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
        if !config.hasAcknowledgedCloudSharing {
            VStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.accent)

                Text("onboarding.experience.practice.cloudBody")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    config.hasAcknowledgedCloudSharing = true
                } label: {
                    Text("onboarding.experience.practice.cloudAction")
                        .primaryButton()
                }
                .buttonStyle(.plain)
            }
            .practiceSetupCard(palette: palette)
        } else if isPreparingManagedPractice {
            VStack(spacing: Spacing.md) {
                ProgressView()
                    .tint(palette.accent)
                Text("onboarding.experience.practice.preparingCredits")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .practiceSetupCard(palette: palette)
        } else if managedPracticeFailed {
            VStack(spacing: Spacing.md) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.warning)
                Text("onboarding.experience.practice.creditsFailed")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("onboarding.experience.practice.retry") {
                    prepareManagedPractice()
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.accent)
                Button("onboarding.experience.practice.skip") {
                    goToLoginReward()
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
            }
            .practiceSetupCard(palette: palette)
        } else {
            VStack(spacing: Spacing.md) {
                if practiceFeature == .voiceInput {
                    practiceVoiceSample
                } else if practiceFeature == .clipboardTranslate
                    || practiceFeature == .clipboardReply {
                    practiceClipboardSample
                }
                practiceEditor
                HStack(spacing: Spacing.xs) {
                    if managedPracticeReady {
                        ProgressView()
                            .controlSize(.small)
                            .tint(palette.accent)
                    }
                    Text("onboarding.experience.practice.waiting")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Button("onboarding.experience.practice.skip") {
                    goToLoginReward()
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var accountOperationError: some View {
        if let key = accountSession.operationErrorKey {
            Text(LocalizedStringKey(key))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.warning)
                .multilineTextAlignment(.center)
        }
    }

    private var practiceEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: practiceFeature == .askAI ? "sparkles" : "message.fill")
                    .foregroundStyle(palette.accent)
                Text(practiceFeature.progressKey)
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
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(keyboardReady ? palette.accent.opacity(0.42) : palette.divider, lineWidth: 1)
        )
    }

    private var practiceVoiceSample: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("onboarding.experience.practice.readAloud")
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textSecondary)

            Text("onboarding.experience.practice.voiceSample")
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
            Text("onboarding.experience.practice.sample")
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
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private var practiceTitle: LocalizedStringKey {
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

    private var practiceSubtitle: LocalizedStringKey {
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
                Image(systemName: accountSession.isSignedIn ? "checkmark.seal.fill" : "gift.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(palette.accent)
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
                        Text("onboarding.experience.login.balance \(balance)")
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

                Button("onboarding.experience.login.skip") {
                    goToComplete()
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
                .opacity(accountSession.isSignedIn ? 0 : 1)
                .disabled(accountSession.isSignedIn)
                .accessibilityHidden(accountSession.isSignedIn)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.xl)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
            .padding(.top, Spacing.xxl)
            .accessibilityIdentifier("onboarding.loginReward.card")
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

                ZStack {
                    Circle()
                        .fill(palette.accentMuted)
                        .frame(width: 108, height: 108)
                    Image(systemName: completedAllPracticeFeatures ? "checkmark" : "sparkles")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }

                Text(
                    completedAllPracticeFeatures
                        ? "onboarding.experience.complete.verifiedTitle"
                        : "onboarding.experience.complete.title"
                )
                .font(TypeStyle.largeTitle)
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, Spacing.xxl)

                Text("onboarding.experience.complete.subtitle")
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
    }

    private func capability(_ icon: String, _ title: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(title)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.medium))
    }

    // MARK: - Bottom action

    private var bottomAction: some View {
        Button(action: performPrimaryAction) {
            HStack(spacing: Spacing.xs) {
                if isRequestingPermissions || (currentStep == .keyboardSwitch && !keyboardReady) {
                    ProgressView()
                        .tint(palette.textOnAccent)
                }
                Text(primaryActionTitle)
            }
            .primaryButton()
        }
        .buttonStyle(.plain)
        .disabled(primaryActionDisabled)
        .opacity(primaryActionDisabled ? 0.55 : 1)
    }

    private var primaryActionDisabled: Bool {
        if isRequestingPermissions || (currentStep == .keyboardSwitch && !keyboardReady) {
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

    private var primaryActionTitle: LocalizedStringKey {
        switch currentStep {
        case .introduction:
            return "onboarding.experience.intro.action"
        case .permissions:
            if permissionsReady { return "common.continue" }
            if micStatus == .denied || speechPermissionDenied {
                return "onboarding.permission.openSettings"
            }
            return "common.continue"
        case .keyboard:
            if keyboardReady { return "common.continue" }
            return hasOpenedKeyboardSettings
                ? "common.continue"
                : "onboarding.enable.openSettings"
        case .keyboardSwitch:
            return keyboardReady
                ? "common.continue"
                : "onboarding.experience.keyboardSwitch.waitingAction"
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
        switch currentStep {
        case .introduction:
            goForward()
        case .permissions:
            handlePermissionAction()
        case .keyboard:
            if keyboardReady || hasOpenedKeyboardSettings {
                goForward()
            } else {
                openKeyboardSettings()
            }
        case .keyboardSwitch:
            guard keyboardReady else { return }
            goForward()
        case .practice:
            guard completedAllPracticeFeatures else { return }
            goToLoginReward()
        case .loginReward:
            goToComplete()
        case .complete:
            finishOnboarding()
        }
    }

    // MARK: - State and actions

    private var permissionsReady: Bool {
        micStatus == .granted && speechStatus == .granted
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

    private func openKeyboardSettings() {
        hasOpenedKeyboardSettings = true
        AppPermissions.openSystemSettings()
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
            guard currentStep == .keyboardSwitch, !keyboardReady else { return }
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
        guard !keyboardReady else { return }
        focusKeyboardSwitchField()

        while !Task.isCancelled, currentStep == .keyboardSwitch {
            refreshState()
            if keyboardReady {
                keyboardVerificationTimedOut = false
                keyboardSwitchFieldFocused = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            didCopyPracticeSample = false
        }
        focusPracticeField()
    }

    private func copyPracticeSample() {
        guard let sessionID = practiceSessionID else { return }
        let sample = AppL10n.string("onboarding.experience.practice.sample")
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
        keyboardAppeared = KeyboardSetupBridge.hasAppeared
        keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    }

    private func goForward() {
        let next: OnboardingExperienceStep
        switch currentStep {
        case .introduction:
            next = .permissions
        case .permissions:
            next = .keyboard
        case .keyboard:
            next = keyboardReady ? .practice : .keyboardSwitch
        case .keyboardSwitch:
            next = .practice
        case .practice:
            next = .loginReward
        case .loginReward, .complete:
            next = .complete
        }
        if next == .practice {
            resetPracticeRun()
        }
        withAnimation(Motion.soft) {
            config.onboardingPage = next.rawValue
        }
    }

    private func goBack() {
        let previous: OnboardingExperienceStep
        switch currentStep {
        case .introduction, .permissions:
            previous = .introduction
        case .keyboard:
            previous = .permissions
        case .keyboardSwitch:
            previous = .keyboard
        case .practice:
            previous = .keyboardSwitch
        case .loginReward:
            previous = .practice
        case .complete:
            previous = .loginReward
        }
        if previous == .practice {
            resetPracticeRun()
        }
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
        withAnimation(Motion.soft) {
            config.onboardingPage = OnboardingExperienceStep.complete.rawValue
        }
    }

    private func goToLoginReward() {
        endPractice()
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

private extension View {
    func practiceSetupCard(palette: ThemePalette) -> some View {
        frame(maxWidth: .infinity, minHeight: 172)
            .padding(Spacing.lg)
            .background(
                palette.surface,
                in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
    }
}

private struct OnboardingExperienceShell<Content: View>: View {
    @Environment(\.themePalette) private var palette

    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let onBack: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("common.back"))
                    Spacer()
                }

                VStack(spacing: Spacing.sm) {
                    Text(title)
                        .font(TypeStyle.largeTitle)
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
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

private struct KeyboardSettingsPreview: View {
    @Environment(\.themePalette) private var palette

    let isReady: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("onboarding.experience.keyboard.previewTitle")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .frame(height: 42)

            Divider().overlay(palette.divider)

            HStack(spacing: Spacing.md) {
                Image("OSGBrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)

                Text("OSGKeyboard")
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                ZStack(alignment: isReady ? .trailing : .leading) {
                    Capsule()
                        .fill(isReady ? palette.accent : palette.surfaceElevated)
                        .frame(width: 48, height: 28)
                    Circle()
                        .fill(isReady ? palette.textOnAccent : palette.textTertiary)
                        .frame(width: 22, height: 22)
                        .padding(3)
                }
                .animation(Motion.quick, value: isReady)
                .accessibilityHidden(true)
            }
            .padding(Spacing.md)
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.dividerStrong, lineWidth: 0.5)
        )
    }
}
