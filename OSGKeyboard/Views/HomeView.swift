// HomeView.swift
// OSGKeyboard · Main App
//
// Minimal home: logo, status capsule, flow hints, inline preview field.
//
// v0.2.0: removed the on-device model warm-up / download state machine
// (Qwen3 CoreML is gone). The local engine uses iOS 26 `SpeechAnalyzer`
// which is always ready, so the previous "model warming / download"
// capsule states collapse into a single "ready" line.

import SwiftUI
import OSGKeyboardShared
import UIKit

struct HomeView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @FocusState private var previewFocused: Bool
    @State private var previewText = ""
    @State private var keyboardHintDismissed = HomeGuideState.isKeyboardHintDismissed
    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus

    private var sessionIsLive: Bool {
        flowManager.isActive || flowManager.isStarting
    }

    private var needsCloudSetup: Bool {
        !config.isLocalEngine && !config.isConfigured
    }

    private var needsPermissionSetup: Bool {
        micStatus != .granted || speechStatus != .granted
    }

    private var shouldShowKeyboardHint: Bool {
        !keyboardHintDismissed
            && !KeyboardSetupBridge.isReadyForOnboardingSkip
            && !needsPermissionSetup
            && flowManager.sessionWarning == nil
            && !needsCloudSetup
    }

    var body: some View {
        GeometryReader { geo in
            let gradientHeight = geo.size.height * 0.30 + geo.safeAreaInsets.top

            ZStack(alignment: .top) {
                sessionHeaderGradient(height: gradientHeight)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    logoHeader
                        .padding(.top, Spacing.xxxl)
                        .padding(.bottom, Spacing.xxl)

                    if showsFlowSessionExtras {
                        flowSessionExtras
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.lg)
                    }

                    HomeStatsCard()
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.md)

                    previewField
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    HStack(spacing: Spacing.sm) {
                        engineStatusLine
                        flowStatusFooter
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.xl)
                    .padding(.bottom, Spacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(palette.background)
            .contentShape(Rectangle())
            .onTapGesture {
                if previewFocused {
                    previewFocused = false
                }
            }
        }
        .onAppear {
            refreshPermissionStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionStatuses()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
    }

    private func handlePermissionGuidanceAction() {
        if AppPermissions.canRequestPermissionsInApp {
            Task {
                await AppPermissions.requestFlowPermissionsIfNeeded()
                refreshPermissionStatuses()
            }
        } else {
            AppPermissions.openSystemSettings()
        }
    }

    // MARK: - Top gradient

    private func sessionHeaderGradient(height: CGFloat) -> some View {
        LinearGradient(
            colors: headerGradientColors,
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .animation(Motion.soft, value: sessionIsLive)
    }

    private var headerGradientColors: [Color] {
        if sessionIsLive {
            return [
                palette.accent.opacity(0.28),
                palette.accent.opacity(0.10),
                palette.background.opacity(0)
            ]
        }
        return [
            palette.textTertiary.opacity(0.14),
            palette.textTertiary.opacity(0.05),
            palette.background.opacity(0)
        ]
    }

    // MARK: - Header

    private var logoHeader: some View {
        VStack(spacing: Spacing.xxl) {
            Image("osglogo")
                .resizable()
                .scaledToFit()
                .frame(width: 144, height: 41)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    // 就绪信息：绿点 + 状态文字（+ 计时 / 结束文本按钮），字号对齐引擎信息行。
    private var flowStatusFooter: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(flowStatusColor)
                .frame(width: 6, height: 6)

            if flowManager.isActive,
               let expires = flowManager.sessionExpiresAt {
                Text("home.flow.label")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                Text(":")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                Text(expires, style: .timer)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            } else {
                Text(flowCapsuleStatusMessage)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            if flowManager.isActive {
                Button {
                    flowManager.endSession()
                } label: {
                    Text("home.flow.endShort")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .animation(Motion.soft, value: flowManager.isActive)
    }

    // MARK: - Flow extras (warnings / hints)

    private var showsFlowSessionExtras: Bool {
        needsPermissionSetup
            || flowManager.sessionWarning != nil
            || needsCloudSetup
            || shouldShowKeyboardHint
            || !flowManager.isActive
    }

    @ViewBuilder
    private var flowSessionExtras: some View {
        if needsPermissionSetup {
            setupGuidanceCard {
                Text(AppPermissions.homePermissionGuidanceMessage)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: handlePermissionGuidanceAction) {
                    Text(
                        AppPermissions.canRequestPermissionsInApp
                            ? "home.setup.permission.request"
                            : "home.flow.openSettings"
                    )
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        } else if let warning = flowManager.sessionWarning {
            setupGuidanceCard {
                Text(warning)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if needsCloudSetup {
            setupGuidanceCard {
                Text("home.setup.cloudIncomplete")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if shouldShowKeyboardHint {
            setupGuidanceCard {
                Text("home.setup.keyboardHint")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    keyboardHintDismissed = true
                    HomeGuideState.dismissKeyboardHint()
                } label: {
                    Text("home.setup.keyboardHint.dismiss")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("home.flow.hint")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.sm)
        }
    }

    private func setupGuidanceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private var flowStatusColor: Color {
        if flowManager.isActive { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if needsPermissionSetup { return palette.warning }
        if flowManager.sessionWarning != nil { return palette.warning }
        return palette.textTertiary
    }

    /// Single source of truth for the logo status capsule. The local
    /// engine is always "ready" in v0.2.0 (iOS `SpeechAnalyzer` ships
    /// with the OS), so the previous downloading / warming / failed
    /// states collapse into the cloud-engine branch.
    private var flowCapsuleStatusMessage: String {
        if flowManager.isStarting {
            return AppL10n.string("home.flow.starting")
        }
        if flowManager.isActive {
            return AppL10n.string("home.flow.label")
        }
        return AppL10n.string("home.flow.inactive")
    }

    // MARK: - Preview field

    private var previewField: some View {
        TextField("home.preview.placeholder", text: $previewText, axis: .vertical)
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.accent)
            .focused($previewFocused)
            .lineLimit(1...100)
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(previewFocused ? palette.dividerStrong : palette.dividerStrong.opacity(0.75), lineWidth: 1)
            )
            // TextField only hit-tests the text line(s); expand taps to the full card.
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .onTapGesture { previewFocused = true }
    }

    private var engineStatusLine: some View {
        Text(
            EngineServiceLabel.summary(
                engineMode: config.engineMode,
                providerId: config.providerId,
                model: config.model
            )
        )
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textSecondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Home guidance persistence

private enum HomeGuideState {
    private static let keyboardHintDismissedKey = "home.keyboardHintDismissed"

    static var isKeyboardHintDismissed: Bool {
        guard AppGroup.isAvailable else { return false }
        return AppGroup.defaults.bool(forKey: keyboardHintDismissedKey)
    }

    static func dismissKeyboardHint() {
        guard AppGroup.isAvailable else { return }
        AppGroup.defaults.set(true, forKey: keyboardHintDismissedKey)
    }
}