// HomeView.swift
// OSGKeyboard · Main App
//
// Home: logo, transient Flow connection status, usage stats, history +
// dictionary entry card. History/dictionary
// open via push (system back) rather than bottom-tab destinations.

import OSGKeyboardShared
import SwiftUI
import UIKit

private enum HomeRoute: Hashable {
    case history
    case dictionary
}

enum FlowHomePiPStatusDescriptor: Equatable {
    case text(localizationKey: String)
    case progress(localizationKey: String, attempt: Int, total: Int)
}

enum FlowHomePiPStatusPolicy {
    static func descriptor(
        lifecycle: FlowPiPLifecycleState,
        isStarting: Bool,
        isRecording: Bool,
        isProcessing: Bool,
        isActive: Bool,
        isHostReady: Bool
    ) -> FlowHomePiPStatusDescriptor {
        switch lifecycle {
        case .preparing(let attempt, let total):
            return .progress(
                localizationKey: "home.flow.preparingProgress",
                attempt: attempt,
                total: total
            )
        case .recovering(let attempt, let total):
            return .progress(
                localizationKey: "home.flow.recoveringProgress",
                attempt: attempt,
                total: total
            )
        case .waitingForForeground:
            return .text(localizationKey: "home.flow.waitingForForeground")
        case .failed:
            return .text(localizationKey: "home.flow.recoveryFailed")
        case .inactive, .active:
            break
        }
        if isStarting {
            return .text(localizationKey: "home.flow.starting")
        }
        if isRecording {
            return .text(localizationKey: "home.flow.recording")
        }
        if isProcessing {
            return .text(localizationKey: "home.flow.processing")
        }
        if isActive, isHostReady {
            return .text(localizationKey: "home.flow.label")
        }
        if isActive {
            // Session flag is up but the ready contract is not — do not lie.
            return .text(localizationKey: "home.flow.notReady")
        }
        return .text(localizationKey: "home.flow.inactive")
    }

    static func canRetry(
        lifecycle: FlowPiPLifecycleState,
        needsPermissionSetup: Bool
    ) -> Bool {
        guard case .failed = lifecycle else { return false }
        return !needsPermissionSetup
    }

    static func shouldShowConnectionCard(
        lifecycle: FlowPiPLifecycleState,
        needsPermissionSetup: Bool,
        needsAPIKeySetup: Bool,
        hasSessionWarning: Bool,
        isRecording: Bool,
        isProcessing: Bool,
        isHostReady: Bool
    ) -> Bool {
        if needsPermissionSetup || needsAPIKeySetup || hasSessionWarning {
            return true
        }
        if isRecording || isProcessing {
            return false
        }
        if case .active = lifecycle {
            return !isHostReady
        }
        return true
    }
}

struct HomeView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var speechHistory = SpeechHistoryStore.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var path = NavigationPath()
    @State private var dictionaryPreviewEntries: [PersonalDictionary.Entry] = []

    private var usesWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var sessionIsLive: Bool {
        flowManager.isActive || flowManager.isStarting
    }

    /// Cloud: ASR + polish keys. Local: polish LLM key (ASR is on-device).
    private var needsAPIKeySetup: Bool {
        if config.isLocalEngine {
            return !config.isPolishConfigured
        }
        return !config.isConfigured
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

    private var canRetryPiP: Bool {
        FlowHomePiPStatusPolicy.canRetry(
            lifecycle: flowManager.pipLifecycleState,
            needsPermissionSetup: needsPermissionSetup
        )
    }

    private var canEndFlowSession: Bool {
        if flowManager.isActive || flowManager.isStarting { return true }
        switch flowManager.pipLifecycleState {
        case .waitingForForeground, .failed:
            return true
        case .inactive, .preparing, .recovering, .active:
            return false
        }
    }

    /// Healthy sessions need no persistent chrome. Keep the connection card
    /// only for setup, startup, recovery, or a genuinely unavailable session.
    private var showsFlowConnectionCard: Bool {
        FlowHomePiPStatusPolicy.shouldShowConnectionCard(
            lifecycle: flowManager.pipLifecycleState,
            needsPermissionSetup: needsPermissionSetup,
            needsAPIKeySetup: needsAPIKeySetup,
            hasSessionWarning: flowManager.sessionWarning != nil,
            isRecording: flowManager.isUtteranceRecording,
            isProcessing: flowManager.isUtteranceProcessing,
            isHostReady: FlowSessionBridge.isHostReady()
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if usesWideLayout {
                    wideBody
                } else {
                    phoneBody
                }
            }
            .toolbar(path.isEmpty ? .hidden : .automatic, for: .navigationBar)
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .history:
                    HistoryView()
                case .dictionary:
                    PersonalDictionaryView()
                }
            }
        }
        .onAppear {
            refreshPermissionStatuses()
            refreshDictionaryPreview()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionStatuses()
            refreshDictionaryPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
            refreshDictionaryPreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
            refreshDictionaryPreview()
        }
        .onChange(of: path.count) { _, count in
            guard count == 0 else { return }
            refreshDictionaryPreview()
        }
    }

    // MARK: - Phone layout

    private var phoneBody: some View {
        GeometryReader { geo in
            let gradientHeight = geo.size.height * 0.30 + geo.safeAreaInsets.top
            let isCompact = geo.size.height < 700
            let logoTopPadding = isCompact ? Spacing.lg : Spacing.xxl
            let logoBottomPadding = isCompact ? Spacing.lg : Spacing.xxl
            let extrasBottomPadding = isCompact ? Spacing.sm : Spacing.lg

            ZStack(alignment: .top) {
                sessionHeaderGradient(height: gradientHeight)
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 0) {
                        logoHeader(compact: isCompact)
                            .padding(.top, logoTopPadding)
                            .padding(.bottom, logoBottomPadding)

                        // Connection status is transient: once Flow is ready,
                        // content moves up and the card disappears completely.
                        if showsFlowConnectionCard {
                            scrollStatusFooter
                                .padding(.horizontal, Spacing.lg)
                                .padding(.bottom, extrasBottomPadding)
                        }

                        HomeUsageStatsSection(layout: .stacked, compact: isCompact)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.md)

                        homeLibrarySection
                            .padding(.horizontal, Spacing.lg)
                            .padding(.bottom, Spacing.xl)
                    }
                    .frame(maxWidth: .infinity)
                    .tabBarScrollBottomPadding()
                }
            }
            .background(palette.background)
        }
    }

    /// Compact Flow connection status — no engine/model details.
    private var scrollStatusFooter: some View {
        setupGuidanceCard {
            flowStatusFooter
        }
    }

    // MARK: - Wide layout (iPad / regular width)

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                wideHeroHeader

                if showsFlowConnectionCard {
                    scrollStatusFooter
                }

                HomeUsageStatsSection(layout: .split)

                homeLibrarySection
            }
            .padding(.horizontal, WideLayoutMetrics.pageHorizontalInset)
            .padding(.top, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .tabBarScrollBottomPadding()
        }
        .background(palette.background)
    }

    private var wideHeroHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("onboarding.welcome.tagline")
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

    // MARK: - History / dictionary cards

    /// Two independent cards; each header is an accent icon + uppercase label
    /// and the body grows with its rows.
    private var homeLibrarySection: some View {
        VStack(spacing: Spacing.md) {
            historyCard
            dictionaryCard
        }
    }

    private var historyCard: some View {
        let entries = Array(speechHistory.entries.prefix(Self.libraryPreviewLimit))
        return homeLibraryCard(
            titleKey: "history.title",
            systemImage: "clock.arrow.circlepath",
            route: .history
        ) {
            if entries.isEmpty {
                libraryEmptyLine("home.card.history.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { libraryRowDivider }
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                            Text(entry.text)
                                .font(TypeStyle.footnote)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: Spacing.xs)
                            Text(Self.previewTimeFormatter.string(from: entry.createdAt))
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                    }
                }
            }
        }
    }

    private var dictionaryCard: some View {
        homeLibraryCard(
            titleKey: "settings.personalDictionary.title",
            systemImage: "character.book.closed",
            route: .dictionary
        ) {
            if dictionaryPreviewEntries.isEmpty {
                libraryEmptyLine("home.card.dictionary.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dictionaryPreviewEntries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { libraryRowDivider }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.term)
                                .font(TypeStyle.body)
                                .foregroundStyle(palette.textPrimary)
                                .lineLimit(1)
                            Text(dictionaryDetailLine(for: entry))
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Spacing.sm)
                    }
                }
            }
        }
    }

    /// Card shell: accent icon + label top-left, chevron trailing, custom body.
    private func homeLibraryCard<Content: View>(
        titleKey: LocalizedStringKey,
        systemImage: String,
        route: HomeRoute,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .symbolRenderingMode(.hierarchical)
                    Text(titleKey)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                content()
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .surfaceCard()
        .accessibilityElement(children: .combine)
    }

    private var libraryRowDivider: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(height: 0.5)
    }

    private func libraryEmptyLine(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(TypeStyle.footnote)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Spacing.xs)
    }

    /// Source · uses · aliases — same secondary line as the dictionary page rows.
    private func dictionaryDetailLine(for entry: PersonalDictionary.Entry) -> String {
        var parts = [SharedL10n.string(entry.source.labelKey, language: config.uiLanguage)]
        if entry.usageCount > 1 {
            let format = AppL10n.string(
                "settings.personalDictionary.usageCount",
                language: config.uiLanguage
            )
            parts.append(String(format: format, entry.usageCount))
        }
        if !entry.aliases.isEmpty {
            parts.append(entry.aliases.joined(separator: " / "))
        }
        return parts.joined(separator: " · ")
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
    }

    private func refreshDictionaryPreview() {
        dictionaryPreviewEntries = AppGroupStore().personalDictionary.entries
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.usageCount > rhs.usageCount
            }
            .prefix(Self.libraryPreviewLimit)
            .map { $0 }
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
        if sessionIsLive, !needsAPIKeySetup {
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

            if needsPermissionSetup || needsAPIKeySetup {
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

            if needsPermissionSetup {
                Button(action: handlePermissionGuidanceAction) {
                    Text(
                        AppPermissions.canRequestPermissionsInApp
                            ? "home.setup.permission.request"
                            : "home.flow.openSettings"
                    )
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            } else if needsAPIKeySetup {
                EmptyView()
            } else if canRetryPiP {
                Button {
                    flowManager.retryPiPRecovery()
                } label: {
                    Text("home.flow.retry")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
                Button {
                    flowManager.endSession()
                } label: {
                    Text("home.flow.endShort")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            } else if canEndFlowSession {
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
                // Foreground activation is automatic. After an explicit stop
                // while staying on this screen, Start is the explicit re-entry.
                Button {
                    flowManager.activateOnForeground(
                        reason: "HomeView.startButton",
                        startCapture: true
                    )
                } label: {
                    Text("home.flow.startShort")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            }
        }
        .animation(Motion.soft, value: flowManager.isActive)
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
        if needsAPIKeySetup { return palette.warning }
        if flowManager.isUtteranceRecording { return palette.accent }
        if flowManager.isUtteranceProcessing { return palette.accent }
        if case .failed = flowManager.pipLifecycleState { return palette.warning }
        if case .waitingForForeground = flowManager.pipLifecycleState { return palette.warning }
        if flowManager.isActive, FlowSessionBridge.isHostReady() { return palette.accent }
        if flowManager.isStarting { return palette.accent }
        if needsPermissionSetup { return palette.warning }
        if flowManager.sessionWarning != nil { return palette.warning }
        // Active but not host-ready (e.g. mid-utterance / audio proof) — amber.
        if flowManager.isActive { return palette.warning }
        return palette.textTertiary
    }

    /// Single source of truth for the logo status capsule. The local
    /// engine is always "ready" because iOS `SpeechAnalyzer` ships
    /// with the OS), so the previous downloading / warming / failed
    /// states collapse into the cloud-engine branch.
    private var flowCapsuleStatusMessage: String {
        let descriptor = FlowHomePiPStatusPolicy.descriptor(
            lifecycle: flowManager.pipLifecycleState,
            isStarting: flowManager.isStarting,
            isRecording: flowManager.isUtteranceRecording,
            isProcessing: flowManager.isUtteranceProcessing,
            isActive: flowManager.isActive,
            isHostReady: FlowSessionBridge.isHostReady()
        )
        switch descriptor {
        case .text(let localizationKey):
            return AppL10n.string(localizationKey)
        case .progress(let localizationKey, let attempt, let total):
            return AppL10n.format(localizationKey, attempt, total)
        }
    }

    /// Rows shown inside the history / dictionary preview cards.
    private static let libraryPreviewLimit = 3

    private static let previewTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
