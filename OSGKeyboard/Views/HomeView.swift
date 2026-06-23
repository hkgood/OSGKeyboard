// HomeView.swift
// OSGKeyboard · Main App
//
// Minimal home: logo, status capsule, flow hints, inline preview field.

import SwiftUI
import OSGKeyboardShared
import UIKit

struct HomeView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var modelWarmup = OnDeviceModelWarmup.shared
    @ObservedObject private var modelManager = ModelManager.shared
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
            && !localModelNeedsAttention
    }

    /// Local engine still needs model download and/or in-memory warm-up.
    private var localModelNeedsAttention: Bool {
        guard config.isLocalEngine else { return false }
        if config.isLocalEngine, config.localASRBackend == .qwen3ASR,
           !OnDeviceMLRuntime.supportsOnDeviceQwen3 { return true }
        if isAnyModelDownloading { return true }
        if !OnDeviceModelStatus.isLocalStackReady(asrBackend: config.localASRBackend) {
            return true
        }
        switch modelWarmup.phase {
        case .ready, .notNeeded:
            return false
        case .warming, .failed, .idle:
            // `.idle` with a downloaded stack means warm-up has not finished yet.
            return true
        }
    }

    private var isAnyModelDownloading: Bool {
        if !modelManager.activeDownloads.isEmpty { return true }
        return OnDeviceModel.allCases.contains { model in
            if case .downloading = modelManager.states[model]?.download { return true }
            return OnDeviceModelStatus.downloadProgress(model) != nil
        }
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
                        .padding(.bottom, Spacing.xl)

                    if showsFlowSessionExtras {
                        flowSessionExtras
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.lg)
                    }

                    previewField
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    engineStatusLine
                        .padding(.horizontal, Spacing.lg)
                        .padding(.top, Spacing.xl)
                        .padding(.bottom, Spacing.sm)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(palette.background)
        }
        .onAppear {
            refreshPermissionStatuses()
            scheduleModelWarmup(force: modelWarmup.phase.isFailed)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionStatuses()
            if config.isLocalEngine {
                OnDeviceModelWarmup.shared.ensureReadyAfterBackground()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
        }
        .onAppear { scheduleModelWarmup() }
        .onChange(of: config.engineMode) { _, _ in scheduleModelWarmup(force: true) }
        .onChange(of: config.localASRBackend) { _, _ in
            modelWarmup.invalidate()
            scheduleModelWarmup(force: true)
        }
        .onChange(of: modelWarmup.phase) { _, phase in
            if phase == .idle, config.isLocalEngine {
                scheduleModelWarmup()
            }
        }
    }

    private func scheduleModelWarmup(force: Bool = false) {
        guard config.isLocalEngine else {
            modelWarmup.invalidate()
            return
        }
        modelWarmup.warmUpIfNeeded(force: force)
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
        if AppPermissions.flowRequirementsMet {
            flowManager.autoStartIfNeeded()
        }
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
        .animation(Motion.soft, value: localModelNeedsAttention)
    }

    private var headerGradientColors: [Color] {
        if localModelNeedsAttention {
            return [
                palette.warning.opacity(0.32),
                palette.warning.opacity(0.12),
                palette.background.opacity(0)
            ]
        }
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

            statusCapsule
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    private var statusCapsule: some View {
        HStack(spacing: Spacing.sm) {
            flowCapsuleSegment

            if flowManager.isActive {
                Button {
                    flowManager.endSession()
                } label: {
                    Text("home.flow.endShort")
                        .font(TypeStyle.caption)
                        .foregroundStyle(palette.textOnAccent)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(capsuleBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(palette.divider, lineWidth: 0.5)
        )
        .animation(Motion.soft, value: flowManager.isActive)
    }

    @ViewBuilder
    private var flowCapsuleSegment: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(flowStatusColor)
                .frame(width: 6, height: 6)

            if flowManager.isActive,
               let expires = flowManager.sessionExpiresAt,
               !localModelNeedsAttention {
                Text("home.flow.label")
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textPrimary)
                Text(":")
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textTertiary)
                Text(expires, style: .timer)
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            } else {
                Text(flowCapsuleStatusMessage)
                    .font(TypeStyle.status)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var capsuleBackground: Color {
        sessionIsLive
            ? palette.accentMuted.opacity(0.55)
            : palette.surface.opacity(0.88)
    }

    // MARK: - Flow extras (warnings / hints)

    private var showsFlowSessionExtras: Bool {
        needsPermissionSetup
            || flowManager.sessionWarning != nil
            || needsCloudSetup
            || shouldShowKeyboardHint
            || (!flowManager.isActive && !localModelNeedsAttention)
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
        if localModelNeedsAttention { return palette.warning }
        if flowManager.isActive { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if needsPermissionSetup { return palette.warning }
        if flowManager.sessionWarning != nil { return palette.warning }
        return palette.textTertiary
    }

    /// Single source of truth for the logo status capsule (local model + flow state).
    private var flowCapsuleStatusMessage: String {
        if config.isLocalEngine, config.localASRBackend == .qwen3ASR,
           !OnDeviceMLRuntime.supportsOnDeviceQwen3 {
            return AppL10n.string("home.engine.unsupportedOS")
        }
        if config.isLocalEngine {
            if isAnyModelDownloading {
                return AppL10n.string("home.engine.downloading")
            }
            if !OnDeviceModelStatus.isLocalStackReady(asrBackend: config.localASRBackend) {
                return AppL10n.string("home.engine.downloadFirst")
            }
            switch modelWarmup.phase {
            case .warming:
                return AppL10n.string("home.engine.warming")
            case .failed(let message):
                return message
            case .idle:
                return AppL10n.string("home.engine.warming")
            case .ready, .notNeeded:
                break
            }
        }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
            .background(palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(previewFocused ? palette.dividerStrong : palette.divider, lineWidth: 0.5)
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
                model: config.model,
                localASRBackend: config.localASRBackend
            )
        )
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
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
