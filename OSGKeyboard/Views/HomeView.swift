// HomeView.swift
// OSGKeyboard · Main App
//
// Home: logo, transient Flow connection status, usage stats, account rewards,
// and dictionary suggestions. History/dictionary/account destinations open
// via push (system back) rather than bottom-tab destinations.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI
import UIKit

private enum HomeRoute: Hashable {
    case history
    case dictionary
    case account
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

enum HomeServiceSetupPolicy {
    static func apiKeyMessageKey(
        isLocalEngine: Bool,
        isASRConfigured: Bool
    ) -> String {
        if isLocalEngine || isASRConfigured {
            return "home.setup.polishKeyMissing"
        }
        return "home.setup.cloudIncomplete"
    }

    static func apiKeyDeepLink(
        isLocalEngine: Bool,
        isASRConfigured: Bool
    ) -> SettingsDeepLink {
        if isLocalEngine || isASRConfigured {
            return .textPolish
        }
        return .speechRecognition
    }
}

struct HomeView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var path = NavigationPath()
    @State private var dictionarySuggestions: [FrequentTerm] = []
    @State private var pendingDictionarySuggestion: FrequentTerm?

    private let appGroupStore = AppGroupStore()
    private let dictionaryEntryService = PersonalDictionaryEntryService()
    private let frequentTermStore = FrequentTermStore()

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

    private var apiKeySetupMessageKey: LocalizedStringKey {
        LocalizedStringKey(
            HomeServiceSetupPolicy.apiKeyMessageKey(
                isLocalEngine: config.isLocalEngine,
                isASRConfigured: config.isASRConfigured
            )
        )
    }

    private var apiKeySettingsDeepLink: SettingsDeepLink {
        HomeServiceSetupPolicy.apiKeyDeepLink(
            isLocalEngine: config.isLocalEngine,
            isASRConfigured: config.isASRConfigured
        )
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
                case .account:
                    AccountCenterView()
                }
            }
        }
        .navigationStackTabBarVisibility(isRoot: path.isEmpty)
        .onAppear {
            refreshPermissionStatuses()
            refreshDictionarySuggestions()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionStatuses()
            refreshDictionarySuggestions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionStatuses()
            refreshDictionarySuggestions()
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
            refreshDictionarySuggestions()
        }
        .onChange(of: path.count) { _, count in
            guard count == 0 else { return }
            refreshDictionarySuggestions()
        }
    }

    // MARK: - Phone layout

    private var phoneBody: some View {
        GeometryReader { geo in
            let gradientHeight = geo.size.height * 0.30 + geo.safeAreaInsets.top
            let isCompact = geo.size.height < 700
            let logoTopPadding = isCompact ? Spacing.lg : Spacing.xxl
            let logoBottomPadding = isCompact ? Spacing.lg : Spacing.xxl

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
                                .padding(.bottom, CardLayoutMetrics.sectionSpacing)
                        }

                        homeContentSections(layout: .stacked, compact: isCompact)
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
            if needsAPIKeySetup {
                apiKeySetupGuidance
            }
        }
    }

    // MARK: - Wide layout (iPad / regular width)

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CardLayoutMetrics.sectionSpacing) {
                wideHeroHeader

                if showsFlowConnectionCard {
                    scrollStatusFooter
                }

                homeContentSections(layout: .split)
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

    // MARK: - Usage, account, and dictionary

    /// Keep the Home information hierarchy stable on both phone and iPad:
    /// account rewards → four metrics → calendar → personal dictionary.
    private func homeContentSections(
        layout: UsageStatsClusterLayout,
        compact: Bool = false
    ) -> some View {
        VStack(spacing: CardLayoutMetrics.sectionSpacing) {
            AccountRewardsCard {
                path.append(HomeRoute.account)
            }

            HomeUsageStatsSection(
                layout: layout,
                compact: compact,
                content: .metrics,
                onOpenHistory: {
                    path.append(HomeRoute.history)
                },
                onOpenDictionary: {
                    path.append(HomeRoute.dictionary)
                }
            )

            HomeUsageStatsSection(
                layout: layout,
                compact: compact,
                content: .calendar
            )

            dictionaryCard
        }
    }

    private var dictionaryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                path.append(HomeRoute.dictionary)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .symbolRenderingMode(.monochrome)
                    Text("settings.personalDictionary.title")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if dictionarySuggestions.isEmpty {
                Text("home.card.dictionary.smart.empty")
                    .font(TypeStyle.footnote)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                VStack(spacing: Spacing.sm) {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 88, maximum: 160),
                                spacing: CardLayoutMetrics.compactItemSpacing
                            )
                        ],
                        alignment: .leading,
                        spacing: CardLayoutMetrics.compactItemSpacing
                    ) {
                        ForEach(dictionarySuggestions) { suggestion in
                            Button {
                                pendingDictionarySuggestion = suggestion
                            } label: {
                                Text(suggestion.term)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, Spacing.sm)
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(
                                        palette.textPrimary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .popover(
                                isPresented: Binding(
                                    get: {
                                        pendingDictionarySuggestion?.id == suggestion.id
                                    },
                                    set: { isPresented in
                                        if !isPresented,
                                           pendingDictionarySuggestion?.id == suggestion.id {
                                            pendingDictionarySuggestion = nil
                                        }
                                    }
                                ),
                                attachmentAnchor: .rect(.bounds),
                                arrowEdge: .bottom
                            ) {
                                dictionarySuggestionConfirmation(suggestion)
                                    .presentationCompactAdaptation(.popover)
                            }
                            .accessibilityHint(
                                AppL10n.format(
                                    "home.card.dictionary.smart.accessibilityHint",
                                    suggestion.commitCount
                                )
                            )
                        }
                    }

                    Text("home.card.dictionary.smart.addHint")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard()
    }

    private func dictionarySuggestionConfirmation(_ suggestion: FrequentTerm) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(AppL10n.format("home.card.dictionary.confirm.title", suggestion.term))
                .font(TypeStyle.headline)
                .foregroundStyle(palette.textPrimary)

            Text(
                AppL10n.format(
                    "home.card.dictionary.confirm.message",
                    suggestion.commitCount
                )
            )
            .font(TypeStyle.footnote)
            .foregroundStyle(palette.textSecondary)

            HStack(spacing: Spacing.sm) {
                Button("common.cancel") {
                    pendingDictionarySuggestion = nil
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Button("home.card.dictionary.confirm.add") {
                    addSuggestedTerm(suggestion)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 300)
        .background(palette.surface)
    }

    private func refreshPermissionStatuses() {
        micStatus = AppPermissions.micStatus
        speechStatus = AppPermissions.speechStatus
    }

    private func refreshDictionarySuggestions() {
        let dictionary = appGroupStore.personalDictionary
        let suggestions = frequentTermStore.suggestions(
            excludingPersonalTerms: Set(dictionary.entries.map(\.term)),
            limit: Self.dictionarySuggestionLimit
        )
        let visibleSuggestions = Array(suggestions.prefix(Self.dictionarySuggestionLimit))
        dictionarySuggestions = visibleSuggestions.count >= Self.minimumDictionarySuggestionCount
            ? visibleSuggestions
            : []
    }

    private func addSuggestedTerm(_ suggestion: FrequentTerm) {
        guard let saved = dictionaryEntryService.saveEntry(
            term: suggestion.term,
            source: .history,
            minimumUsageCount: suggestion.commitCount
        ) else {
            return
        }
        pendingDictionarySuggestion = nil
        refreshDictionarySuggestions()

        Task {
            await dictionaryEntryService.finishSaving(saved)
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

    private func openSettings(_ deepLink: SettingsDeepLink) {
        SettingsDeepLink.setPending(deepLink)
        NotificationCenter.default.post(name: .osgOpenSettingsDeepLink, object: nil)
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

    // Logo 保持 144:41 比例，并使用随系统深浅色切换的黑白单色。
    private func logoHeader(compact: Bool) -> some View {
        let logoWidth: CGFloat = compact ? 88 : 108
        let logoHeight = logoWidth * (41.0 / 144.0)
        return VStack(spacing: Spacing.xxl) {
            Image("osglogo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: logoWidth, height: logoHeight)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
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
                // The explanatory copy and both setup paths sit below this
                // compact status row so they remain readable on narrow phones.
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

    private var apiKeySetupGuidance: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(apiKeySetupMessageKey)
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("home.setup.credits.alternative")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Spacing.sm) {
                Button {
                    openSettings(apiKeySettingsDeepLink)
                } label: {
                    Label("home.setup.byok.configure", systemImage: "key")
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .frame(minHeight: 34)
                        .background(
                            palette.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    openSettings(.aiService)
                } label: {
                    Label("home.setup.credits.open", systemImage: "sparkles")
                        .foregroundStyle(palette.textOnAccent)
                        .padding(.horizontal, Spacing.sm)
                        .frame(minHeight: 34)
                        .background(
                            palette.accent,
                            in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
            .font(TypeStyle.body)
        }
    }

    private func setupGuidanceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
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

    private static let minimumDictionarySuggestionCount = 3
    private static let dictionarySuggestionLimit = 6
}
