// OnboardingExperienceView.swift
// OSGKeyboard · Main App
//
// A short, outcome-led first run:
//   1) Explain the product and its data boundaries.
//   2) Request the two permissions needed by Flow.
//   3) Guide keyboard installation with a visual system-settings preview.
//   4) Teach on the real keyboard inside a real host text field.
//   5) Celebrate the first verified voice insertion.

import OSGKeyboardShared
import SwiftUI
import UIKit

private enum OnboardingExperienceStep: Int, CaseIterable {
    case introduction
    case permissions
    case keyboard
    case practice
    case complete
}

struct OnboardingExperienceView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var flowManager: FlowSessionManager
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @ObservedObject var config: ProviderConfig
    @ObservedObject private var deployment = RimeDeploymentController.shared

    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var keyboardAppeared = KeyboardSetupBridge.hasAppeared
    @State private var keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    @State private var hasOpenedKeyboardSettings = false
    @State private var isRequestingPermissions = false
    @State private var practiceText = ""
    @State private var practiceStartedAt: Date?
    @State private var didVerifyVoiceInsertion = false
    @State private var isPreparingManagedPractice = false
    @State private var managedPracticeReady = false
    @State private var managedPracticeFailed = false
    @FocusState private var practiceFieldFocused: Bool

    private static let migrationKey = "onboarding.experience.v2.migrated"

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

                if currentStep != .practice {
                    bottomAction
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.lg)
                }
            }
        }
        .onAppear {
            migrateLegacyProgressIfNeeded()
            applyPrivacySafeDefaultsIfNeeded()
            refreshState()
            if currentStep == .practice {
                beginPractice()
            }
        }
        .onDisappear {
            endPractice()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshState()
            if currentStep == .practice {
                beginPracticeIfNeeded()
            }
        }
        .onChange(of: currentStep) { previous, current in
            if previous == .practice {
                endPractice()
            }
            if current == .practice {
                beginPractice()
            }
        }
        .onChange(of: accountSession.isSignedIn) { _, isSignedIn in
            guard isSignedIn, currentStep == .practice,
                  config.hasAcknowledgedCloudSharing else { return }
            prepareManagedPractice()
        }
        .onChange(of: config.hasAcknowledgedCloudSharing) { _, acknowledged in
            guard acknowledged, currentStep == .practice,
                  accountSession.isSignedIn else { return }
            prepareManagedPractice()
        }
        .task(id: currentStep) {
            guard currentStep == .practice else { return }
            await monitorPractice()
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
        case .practice:
            practicePage
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
            KeyboardSettingsPreview(isReady: keyboardReady || hasOpenedKeyboardSettings)
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

                Button("onboarding.experience.practice.skip") {
                    goToComplete()
                }
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
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

                if managedPracticeReady, keyboardReady {
                    Text("onboarding.experience.practice.sample")
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .italic()
                        .padding(.top, Spacing.sm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)

            practiceContent
                .padding(.horizontal, Spacing.lg)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.sm)

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
        if !accountSession.isSignedIn {
            VStack(spacing: Spacing.md) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.accent)

                Text("onboarding.experience.practice.signInBody")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)

                AccountAppleAuthorizationButton(purpose: .signIn)
                    .disabled(accountSession.operation != nil)

                accountOperationError
            }
            .practiceSetupCard(palette: palette)
        } else if !config.hasAcknowledgedCloudSharing {
            VStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(palette.accent)

                Text("onboarding.experience.practice.cloudBody")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)

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
                Button("onboarding.enable.resources.retry") {
                    prepareManagedPractice()
                }
                .font(TypeStyle.bodyEmph)
                .foregroundStyle(palette.accent)
                accountOperationError
            }
            .practiceSetupCard(palette: palette)
        } else {
            practiceEditor
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
                Image(systemName: "message.fill")
                    .foregroundStyle(palette.accent)
                Text("onboarding.experience.practice.editorTitle")
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

    private var practiceTitle: LocalizedStringKey {
        if !permissionsReady {
            return "onboarding.experience.practice.permissionsTitle"
        }
        if !accountSession.isSignedIn {
            return "onboarding.experience.practice.signInTitle"
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
        return "onboarding.experience.practice.speakTitle"
    }

    private var practiceSubtitle: LocalizedStringKey {
        if !permissionsReady {
            return "onboarding.experience.practice.permissionsSubtitle"
        }
        if !accountSession.isSignedIn {
            return "onboarding.experience.practice.signInSubtitle"
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
        return "onboarding.experience.practice.speakSubtitle"
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
                    Image(systemName: didVerifyVoiceInsertion ? "checkmark" : "sparkles")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }

                Text(
                    didVerifyVoiceInsertion
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

                if !practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(practiceText)
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.md)
                        .background(
                            palette.surface,
                            in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                                .stroke(palette.divider, lineWidth: 0.5)
                        )
                        .padding(.top, Spacing.xl)
                }

                HStack(spacing: Spacing.xs) {
                    capability("mic.fill", "onboarding.experience.complete.dictate")
                    capability("sparkles", "onboarding.experience.complete.agent")
                    capability("wand.and.stars", "onboarding.experience.complete.edit")
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
                if isRequestingPermissions {
                    ProgressView()
                        .tint(palette.textOnAccent)
                }
                Text(primaryActionTitle)
            }
            .primaryButton()
        }
        .buttonStyle(.plain)
        .disabled(isRequestingPermissions)
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
            if keyboardReady { return "onboarding.experience.keyboard.practiceAction" }
            return hasOpenedKeyboardSettings
                ? "common.continue"
                : "onboarding.enable.openSettings"
        case .practice:
            return "common.continue"
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
        case .practice:
            break
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
            KeyboardSetupBridge.setOnboardingPracticeActive(true)
            flowManager.activateOnForeground(reason: "onboarding.practice.resume")
            focusPracticeField()
        } else if accountSession.isSignedIn, config.hasAcknowledgedCloudSharing {
            prepareManagedPractice()
        }
    }

    private func beginPractice() {
        refreshState()
        practiceStartedAt = nil
        didVerifyVoiceInsertion = false
        managedPracticeReady = false
        managedPracticeFailed = false
        KeyboardSetupBridge.setOnboardingPracticeActive(false)
        if accountSession.isSignedIn, config.hasAcknowledgedCloudSharing {
            prepareManagedPractice()
        }
    }

    private func prepareManagedPractice() {
        guard currentStep == .practice,
              accountSession.isSignedIn,
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
            let ready = await accountSession.prepareManagedGateway()
            guard currentStep == .practice else { return }
            isPreparingManagedPractice = false
            guard ready else {
                managedPracticeFailed = true
                return
            }

            config.credentialSource = .managed
            managedPracticeReady = true
            practiceStartedAt = Date()
            KeyboardSetupBridge.setOnboardingPracticeActive(true)
            if permissionsReady {
                flowManager.activateOnForeground(reason: "onboarding.practice.managed")
            }
            focusPracticeField()
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
        KeyboardSetupBridge.setOnboardingPracticeActive(false)
    }

    @MainActor
    private func monitorPractice() async {
        while !Task.isCancelled, currentStep == .practice {
            refreshState()
            if let startedAt = practiceStartedAt,
               let insertedAt = KeyboardSetupBridge.lastVoiceInsertionAt,
               insertedAt >= startedAt {
                didVerifyVoiceInsertion = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, currentStep == .practice else { return }
                goToComplete()
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
        }
    }

    private func refreshState() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
        keyboardAppeared = KeyboardSetupBridge.hasAppeared
        keyboardReady = KeyboardSetupBridge.isReadyForOnboardingSkip
    }

    private func goForward() {
        let next = min(currentStep.rawValue + 1, OnboardingExperienceStep.complete.rawValue)
        withAnimation(Motion.soft) {
            config.onboardingPage = next
        }
    }

    private func goBack() {
        let previous = max(currentStep.rawValue - 1, OnboardingExperienceStep.introduction.rawValue)
        withAnimation(Motion.soft) {
            config.onboardingPage = previous
        }
    }

    private func goToComplete() {
        withAnimation(Motion.soft) {
            config.onboardingPage = OnboardingExperienceStep.complete.rawValue
        }
    }

    private func finishOnboarding() {
        endPractice()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            config.hasCompletedOnboarding = true
        }
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
