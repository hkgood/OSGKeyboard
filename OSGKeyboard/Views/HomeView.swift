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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @FocusState private var previewFocused: Bool
    @State private var previewText = ""
    @State private var keyboardHintDismissed = HomeGuideState.isKeyboardHintDismissed
    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var sessionIsLive: Bool {
        flowManager.isActive || flowManager.isStarting
    }

    private var needsCloudSetup: Bool {
        !config.isLocalEngine && !config.isConfigured
    }

    private var needsPermissionSetup: Bool {
        micStatus != .granted || speechStatus != .granted
    }

    /// Can the user start a session right now from the Home footer? Only when
    /// nothing is live/starting and permissions are already granted (otherwise
    /// the permission guidance card is the correct call to action).
    private var canManuallyStartSession: Bool {
        !sessionIsLive && !needsPermissionSetup
    }

    private var shouldShowKeyboardHint: Bool {
        !keyboardHintDismissed
            && !KeyboardSetupBridge.isReadyForOnboardingSkip
            && !needsPermissionSetup
            && flowManager.sessionWarning == nil
            && !needsCloudSetup
    }

    var body: some View {
        Group {
            if usesWideLayout {
                wideBody
            } else {
                phoneBody
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
        .onChange(of: previewFocused) { _, focused in
            guard focused else { return }
            Task { await flowManager.refreshForInlineKeyboardFocus() }
        }
    }

    // MARK: - Phone layout

    private var phoneBody: some View {
        GeometryReader { geo in
            let gradientHeight = geo.size.height * 0.30 + geo.safeAreaInsets.top
            // 小屏（如 iPhone SE）压缩顶部留白，把空间让给自适应的输入框，
            // 避免固定块之和超出视口、底部状态行被 tab 栏遮挡。
            let isCompact = geo.size.height < 700
            // logo 上下留白对称，避免视觉上偏下。
            let logoTopPadding = isCompact ? Spacing.lg : Spacing.xxl
            let logoBottomPadding = isCompact ? Spacing.lg : Spacing.xxl
            let extrasBottomPadding = isCompact ? Spacing.sm : Spacing.lg
            let statusTopPadding = isCompact ? Spacing.sm : Spacing.xl
            // 输入框最小高度：小屏可压得更矮，让底部状态行始终留在 tab 栏之上。
            let previewMinHeight: CGFloat = isCompact ? 72 : 160

            ZStack(alignment: .top) {
                sessionHeaderGradient(height: gradientHeight)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    logoHeader(compact: isCompact)
                        .padding(.top, logoTopPadding)
                        .padding(.bottom, logoBottomPadding)

                    if showsFlowSessionExtras {
                        flowSessionExtras
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, extrasBottomPadding)
                    }

                    HomeUsageStatsSection(layout: .stacked, compact: isCompact)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.md)

                    // 唯一的弹性区块：吸收全部剩余空间（大屏铺满、小屏优先让位）。
                    previewField(minHeight: previewMinHeight)
                        .padding(.horizontal, Spacing.lg)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .layoutPriority(-1)

                    HStack(spacing: Spacing.sm) {
                        engineStatusLine
                        flowStatusFooter
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, statusTopPadding)
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
    }

    // MARK: - Wide layout (iPad / regular width)

    private var wideBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                wideHeroHeader

                HomeUsageStatsSection(layout: .split)

                if showsFlowSessionExtras {
                    flowSessionExtras
                }

                widePreviewStage
            }
            .padding(.horizontal, WideLayoutMetrics.pageHorizontalInset)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(palette.background)
        .contentShape(Rectangle())
        .onTapGesture {
            if previewFocused {
                previewFocused = false
            }
        }
    }

    private var wideHeroHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("home.wide.tagline")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text("home.wide.tagline.subtitle")
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var widePreviewStage: some View {
        WideCard(padding: Spacing.md, cornerRadius: Radius.large) {
            previewFieldContent
                .frame(
                    maxWidth: .infinity,
                    minHeight: WideLayoutMetrics.dictationCanvasMinHeight,
                    maxHeight: .infinity,
                    alignment: .topLeading
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        // 云端引擎未配置（缺 API Key）时不算就绪，保持中性灰渐变。
        if sessionIsLive, !needsCloudSetup {
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

    // logo 尺寸保持 144:41 比例；小屏进一步缩小，给下方内容让空间。
    private func logoHeader(compact: Bool) -> some View {
        let logoWidth: CGFloat = compact ? 104 : 124
        let logoHeight = logoWidth * (41.0 / 144.0)
        return VStack(spacing: Spacing.xxl) {
            Image("osglogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoWidth, height: logoHeight)
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

            if needsCloudSetup {
                // 云端引擎缺 API Key：不显示就绪 / 计时 / 结束按钮。
                Text("home.flow.notReady")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if flowManager.isUtteranceRecording {
                Text("home.flow.recording")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            } else if flowManager.isUtteranceProcessing {
                Text("home.flow.processing")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            } else if flowManager.isActive,
               FlowSessionBridge.isHostReady(),
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

            if needsCloudSetup {
                // 无按钮：引导卡片已提示去设置填 API Key。
                EmptyView()
            } else if flowManager.isActive {
                Button {
                    flowManager.endSession()
                } label: {
                    Text("home.flow.endShort")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            } else if canManuallyStartSession {
                // Sessions auto-start on foreground, but after a manual stop /
                // expiry the user needs a reliable, no-jump way back in.
                Button {
                    flowManager.activateOnForeground()
                } label: {
                    Text("home.flow.startShort")
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
        if needsCloudSetup { return palette.warning }
        if flowManager.isUtteranceRecording { return palette.accent }
        if flowManager.isUtteranceProcessing { return palette.accent }
        if flowManager.isActive, FlowSessionBridge.isHostReady() { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if needsPermissionSetup { return palette.warning }
        if flowManager.sessionWarning != nil { return palette.warning }
        // Active but not host-ready (e.g. mid-utterance / audio proof) — amber.
        if flowManager.isActive { return palette.warning }
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
        if flowManager.isUtteranceRecording {
            return AppL10n.string("home.flow.recording")
        }
        if flowManager.isUtteranceProcessing {
            return AppL10n.string("home.flow.processing")
        }
        if flowManager.isActive, FlowSessionBridge.isHostReady() {
            return AppL10n.string("home.flow.label")
        }
        if flowManager.isActive {
            // Session flag is up but the ready contract is not — do not lie.
            return AppL10n.string("home.flow.notReady")
        }
        return AppL10n.string("home.flow.inactive")
    }

    // MARK: - Preview field

    private func previewField(minHeight: CGFloat) -> some View {
        previewFieldContent
            .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.md)
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(previewFocused ? palette.dividerStrong : palette.dividerStrong.opacity(0.75), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .onTapGesture { previewFocused = true }
    }

    private var previewFieldContent: some View {
        TextField("home.preview.placeholder", text: $previewText, axis: .vertical)
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.accent)
            .focused($previewFocused)
            .lineLimit(1...100)
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