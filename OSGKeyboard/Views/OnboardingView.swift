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

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch OnboardingPage(rawValue: config.onboardingPage) ?? .welcome {
                    case .welcome: WelcomePage()
                    case .microphone:
                        MicPermissionPage(status: $micStatus)
                    case .speech:
                        SpeechPermissionPage(status: $speechStatus)
                    case .keyboard: EnableKeyboardPage()
                    case .api: APISetupPage(config: config)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .trailing)))

                pageDots
                    .padding(.bottom, Spacing.md)

                bottomBar
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .onAppear {
            if config.onboardingPage < 0 || config.onboardingPage >= OnboardingPage.count {
                config.onboardingPage = 0
            }
            refreshPermissionStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshPermissionStatuses() }
        }
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<OnboardingPage.count, id: \.self) { i in
                Capsule()
                    .fill(i == config.onboardingPage ? palette.accent : Color.white.opacity(0.18))
                    .frame(width: i == config.onboardingPage ? 18 : 6, height: 6)
                    .animation(Motion.quick, value: config.onboardingPage)
            }
        }
    }

    private var isLastPage: Bool { config.onboardingPage == OnboardingPage.api.rawValue }

    private var canAdvance: Bool {
        switch OnboardingPage(rawValue: config.onboardingPage) ?? .welcome {
        case .welcome, .keyboard, .api:
            return !isLastPage || config.isConfigured
        case .microphone:
            return micStatus != .undetermined
        case .speech:
            return speechStatus != .undetermined
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: Spacing.sm) {
            if config.onboardingPage > 0 {
                Button { withAnimation(Motion.soft) { config.onboardingPage -= 1 } } label: {
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

            Button {
                withAnimation(Motion.soft) {
                    if isLastPage {
                        config.hasCompletedOnboarding = true
                    } else {
                        config.onboardingPage += 1
                    }
                }
            } label: {
                Text(isLastPage
                     ? NSLocalizedString("common.done", comment: "")
                     : NSLocalizedString("common.next", comment: ""))
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

// MARK: - Welcome

private struct WelcomePage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(palette.accentMuted)
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(palette.accent)
            }
            VStack(spacing: Spacing.sm) {
                Text("OSGKeyboard")
                    .font(TypeStyle.title)
                    .foregroundStyle(palette.textPrimary)
                Text("onboarding.welcome.subtitle")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            PrivacyFootnote()
                .padding(.top, Spacing.lg)
            if let url = LegalLinks.privacyPolicyURL {
                Link(destination: url) {
                    Text("legal.privacyPolicy")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.accent)
                }
                .padding(.top, Spacing.xs)
            }
            Spacer()
        }
    }
}

private struct PrivacyFootnote: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            footnoteRow(icon: "lock.fill", title: "privacy.audio.title", body: "privacy.audio.body")
            footnoteRow(icon: "wifi", title: "privacy.network.title", body: "privacy.network.body")
            footnoteRow(icon: "keyboard", title: "privacy.universal.title", body: "privacy.universal.body")
        }
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
        .padding(.horizontal, Spacing.md)
    }

    private func footnoteRow(icon: String, title: LocalizedStringKey, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accent)
                .frame(width: 24, height: 24)
                .background(palette.accentMuted, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textPrimary)
                Text(body)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }
}

// MARK: - Permission pages

private struct MicPermissionPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Binding var status: AppPermissions.MicStatus
    @State private var isRequesting = false

    var body: some View {
        PermissionPageLayout(
            icon: "mic.fill",
            title: "onboarding.permission.mic.title",
            detail: "onboarding.permission.mic.body",
            status: statusLabel,
            statusColor: statusColor,
            primaryTitle: primaryButtonTitle,
            primaryDisabled: isRequesting || status == .granted,
            onPrimary: { Task { await request() } },
            secondaryTitle: status == .denied ? "onboarding.permission.openSettings" : nil,
            onSecondary: status == .denied ? { AppPermissions.openSystemSettings() } : nil,
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
        case .granted: return palette.success
        case .denied: return palette.warning
        case .undetermined: return palette.textTertiary
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        status == .granted ? "onboarding.permission.status.granted" : "onboarding.permission.mic.allow"
    }

    private func request() async {
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
            secondaryTitle: speechDenied ? "onboarding.permission.openSettings" : nil,
            onSecondary: speechDenied ? { AppPermissions.openSystemSettings() } : nil,
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
        case .granted: return palette.success
        case .denied, .restricted: return palette.warning
        case .undetermined: return palette.textTertiary
        }
    }

    private var primaryButtonTitle: LocalizedStringKey {
        status == .granted
            ? "onboarding.permission.status.granted"
            : "onboarding.permission.speech.allow"
    }

    private func request() async {
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
    let status: LocalizedStringKey
    let statusColor: Color
    let primaryTitle: LocalizedStringKey
    let primaryDisabled: Bool
    let onPrimary: () -> Void
    var secondaryTitle: LocalizedStringKey? = nil
    var onSecondary: (() -> Void)? = nil
    var deniedHint: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(palette.accent)
            VStack(spacing: Spacing.sm) {
                Text(title)
                    .font(TypeStyle.title2)
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(status)
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            if let deniedHint {
                Text(deniedHint)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            VStack(spacing: Spacing.xs) {
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
            .padding(.horizontal, Spacing.md)
            Spacer()
        }
    }
}

// MARK: - Enable keyboard

private struct EnableKeyboardPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            Image(systemName: "keyboard.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(palette.accent)
            VStack(spacing: Spacing.sm) {
                Text("onboarding.enable.title")
                    .font(TypeStyle.title2)
                    .foregroundStyle(palette.textPrimary)
                Text("onboarding.enable.fullAccessNote")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                step(num: 1, text: NSLocalizedString("onboarding.enable.step1", comment: ""))
                step(num: 2, text: NSLocalizedString("onboarding.enable.step2", comment: ""))
                step(num: 3, text: NSLocalizedString("onboarding.enable.step3", comment: ""))
                step(num: 4, text: NSLocalizedString("onboarding.enable.step4", comment: ""))
            }
            .cardSurface()
            .padding(.horizontal, Spacing.md)

            Button {
                AppPermissions.openSystemSettings()
            } label: {
                Label(LocalizedStringKey("onboarding.enable.openSettings"), systemImage: "arrow.up.right.square")
                    .primaryButton()
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Spacing.md)
            Spacer()
        }
    }

    private func step(num: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Text("\(num)")
                .font(TypeStyle.caption2)
                .frame(width: 22, height: 22)
                .background(palette.accent, in: Circle())
                .foregroundStyle(palette.textOnAccent)
            Text(text)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - API setup

private struct APISetupPage: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("onboarding.api.title")
                        .font(TypeStyle.title2)
                        .foregroundStyle(palette.textPrimary)
                    Text("onboarding.api.subtitle")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, Spacing.xxs)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)

                EnginePickerSection(config: config)
                    .padding(.horizontal, Spacing.md)

                if config.engineMode == "cloud" {
                    ProviderPickerSection(config: config)
                        .padding(.horizontal, Spacing.md)
                    APISettingsCard(config: config)
                        .padding(.horizontal, Spacing.md)
                } else {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("onboarding.api.localReady.title")
                                    .font(TypeStyle.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("onboarding.api.localReady.body")
                                    .font(TypeStyle.caption2)
                                    .foregroundStyle(palette.textTertiary)
                            }
                            Spacer()
                        }
                        .padding(Spacing.md)
                    }
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
                    .padding(.horizontal, Spacing.md)
                }
            }
            .padding(.bottom, Spacing.xxxl)
        }
    }
}
