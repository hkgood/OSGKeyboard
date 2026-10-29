// HomeView.swift
// OSGKeyboard · Main App
//
// Home: logo, Flow session status capsule, at most one account surface
// (`HomeAccountSurfacePolicy`), usage stats, and dictionary suggestions.
// History/dictionary/account destinations open via push (system back) rather
// than bottom-tab destinations.

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
}

enum HomeServiceSetupPolicy {
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
    @Environment(\.wideTopCornerClearance) private var topCornerClearance

    @ObservedObject private var config = ProviderConfig.shared
    @EnvironmentObject private var flowManager: FlowSessionManager
    @EnvironmentObject private var accountSession: AccountSessionCoordinator
    @State private var micStatus = AppPermissions.micStatus
    @State private var speechStatus = AppPermissions.speechStatus
    @State private var path = NavigationPath()
    @State private var dictionarySuggestions: [FrequentTerm] = []
    @State private var pendingDictionarySuggestion: FrequentTerm?
    @State private var containerWidth: CGFloat = 0
    /// "Not now" on the invitation card lasts for this launch; the code itself
    /// stays saved and is still redeemed on the next sign-in.
    @State private var isInvitationDeferred = false

    private let appGroupStore = AppGroupStore()
    private let dictionaryEntryService = PersonalDictionaryEntryService()
    private let frequentTermStore = FrequentTermStore()

    private var usesWideLayout: Bool {
        HomeLayoutPolicy.usesWideLayout(
            isRegularWidth: horizontalSizeClass == .regular,
            containerWidth: containerWidth
        )
    }

    private var sessionIsLive: Bool {
        flowManager.isActive || flowManager.isStarting
    }

    private var accountPhase: HomeAccountPhase {
        switch accountSession.sessionPhase {
        case .restoring: return .restoring
        case .signedOut: return .signedOut
        case .signedIn: return .signedIn
        }
    }

    private var serviceReadiness: HomeServiceReadiness {
        HomeAccountSurfacePolicy.readiness(
            credentialSource: config.credentialSource,
            account: accountPhase,
            isASRConfigured: config.isASRConfigured,
            isPolishConfigured: config.isPolishConfigured
        )
    }

    private var creditsState: HomeCreditsState {
        switch accountSession.snapshotPhase {
        case .idle, .loading: return .loading
        case .failed: return .failed
        case .loaded(let snapshot): return .balance(snapshot.credits.balance)
        }
    }

    private var accountSurface: HomeAccountSurface? {
        HomeAccountSurfacePolicy.surface(
            needsPermissionSetup: needsPermissionSetup,
            account: accountPhase,
            pendingReferralCode: accountSession.pendingReferralCode,
            isInvitationDeferred: isInvitationDeferred,
            credentialSource: config.credentialSource,
            readiness: serviceReadiness,
            credits: creditsState
        )
    }

    private var apiKeySettingsDeepLink: SettingsDeepLink {
        HomeServiceSetupPolicy.apiKeyDeepLink(
            isLocalEngine: config.isLocalEngine,
            isASRConfigured: config.isASRConfigured
        )
    }

    /// Credits users first switch the service source; BYOK users go straight
    /// to the missing key.
    private var ownKeySettingsDeepLink: SettingsDeepLink {
        config.credentialSource == .managed ? .aiService : apiKeySettingsDeepLink
    }

    private var needsPermissionSetup: Bool {
        micStatus != .granted || speechStatus != .granted
    }

    /// The permission card already explains why voice input cannot start, and
    /// the split layout's footer already reports the session on every tab.
    private var showsStatusCapsule: Bool {
        !needsPermissionSetup && horizontalSizeClass != .regular
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
        // Folding or unfolding an iPhone Duo changes this width mid-session.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            containerWidth = width
        }
        // Home owns the account refresh now that the summary card is not
        // always on screen; the coordinator's freshness window dedupes calls.
        .task(id: accountSession.accountID) {
            guard accountSession.isSignedIn else { return }
            await accountSession.refreshAccountData()
        }
        .onAppear {
            refreshPermissionStatuses()
            refreshDictionarySuggestions()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refreshPermissionStatuses()
            refreshDictionarySuggestions()
            if accountSession.isSignedIn {
                Task { await accountSession.refreshAccountData() }
            }
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
                            .padding(.bottom, showsStatusCapsule ? Spacing.md : logoBottomPadding)

                        if showsStatusCapsule {
                            flowStatusCapsule
                                .padding(.horizontal, Spacing.lg)
                                .padding(.bottom, logoBottomPadding)
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

    // MARK: - Wide layout (iPad / unfolded iPhone Duo)

    private var wideBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CardLayoutMetrics.sectionSpacing) {
                wideHeroHeader

                homeContentSections(layout: .split)
            }
            .padding(.horizontal, WideLayoutMetrics.pageHorizontalInset)
            .padding(.top, Spacing.sm + topCornerClearance)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .tabBarScrollBottomPadding()
        }
        .background(palette.background)
    }

    private var wideHeroHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(AppL10n.string("onboarding.welcome.tagline"))
                .font(TypeStyle.pageTitle)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(AppL10n.string("home.wide.tagline.subtitle"))
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textTertiary)

            if showsStatusCapsule {
                flowStatusCapsule
                    .padding(.top, Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Usage, account, and dictionary

    /// Keep the Home information hierarchy stable on phone, iPhone Duo, and
    /// iPad: account surface (problem card or summary, never both) → four
    /// metrics → calendar → personal dictionary.
    private func homeContentSections(
        layout: UsageStatsClusterLayout,
        compact: Bool = false
    ) -> some View {
        VStack(spacing: CardLayoutMetrics.sectionSpacing) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--home-dictionary-screenshot") {
                dictionaryCard
            } else if ProcessInfo.processInfo.arguments.contains("--home-calendar-screenshot") {
                HomeUsageStatsSection(layout: layout, compact: compact, content: .calendar)
            } else {
                standardHomeContentSections(layout: layout, compact: compact)
            }
            #else
            standardHomeContentSections(layout: layout, compact: compact)
            #endif
        }
    }

    @ViewBuilder
    private func standardHomeContentSections(
        layout: UsageStatsClusterLayout,
        compact: Bool
    ) -> some View {
            switch accountSurface {
            case .accountSummary:
                AccountRewardsCard(showsOwnKeyNote: config.credentialSource == .byok) {
                    path.append(HomeRoute.account)
                }
            case .signInPromo:
                HomeSignInPromoRow {
                    path.append(HomeRoute.account)
                }
            case let surface?:
                HomeAccountProblemCard(
                    surface: surface,
                    readiness: serviceReadiness,
                    compact: compact,
                    actions: accountSurfaceActions
                )
                .transition(.opacity)
            case nil:
                EmptyView()
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

    private var accountSurfaceActions: HomeAccountSurfaceActions {
        HomeAccountSurfaceActions(
            requestPermissions: handlePermissionGuidanceAction,
            openOwnKeySettings: { openSettings(ownKeySettingsDeepLink) },
            openAccount: { path.append(HomeRoute.account) },
            deferInvitation: {
                withAnimation(Motion.soft) {
                    isInvitationDeferred = true
                }
            }
        )
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
                    Text(AppL10n.string("settings.personalDictionary.title"))
                        .font(TypeStyle.footnote.weight(.semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Spacing.xs)
                    Image(systemName: "chevron.right")
                        .font(TypeStyle.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if dictionarySuggestions.isEmpty {
                Text(AppL10n.string("home.card.dictionary.smart.empty"))
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
                                    .font(TypeStyle.body.weight(.semibold))
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

                    Text(AppL10n.string("home.card.dictionary.smart.addHint"))
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
                Button(AppL10n.string("common.cancel")) {
                    pendingDictionarySuggestion = nil
                }
                .buttonStyle(.bordered)
                .tint(palette.textPrimary)

                Spacer(minLength: 0)

                Button {
                    addSuggestedTerm(suggestion)
                } label: {
                    Text(AppL10n.string("home.card.dictionary.confirm.add"))
                        .foregroundStyle(palette.background)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.textPrimary)
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
        // 云端识别没有可用的 API Key 或积分时不算就绪，保持中性灰渐变。
        if sessionIsLive, serviceReadiness.canDictate {
            let leadingOpacity = colorScheme == .dark ? 0.18 : 0.28
            let trailingOpacity = colorScheme == .dark ? 0.06 : 0.10
            return [
                palette.accent.opacity(leadingOpacity),
                palette.accent.opacity(trailingOpacity),
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
                .foregroundStyle(
                    colorScheme == .dark
                        ? OSGColor.fixedLightContent
                        : OSGColor.fixedDarkContent
                )
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }

    // 会话状态胶囊：圆点 + 状态文字（就绪时附服务来源与计时）+ 开启 / 结束 / 重试。
    // 设置类问题由账号问题卡负责，这里只报告语音会话本身。
    private var flowStatusCapsule: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(flowStatusColor)
                .frame(width: 6, height: 6)

            if !serviceReadiness.canDictate {
                Text(AppL10n.string("home.flow.notReady"))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.warning)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            } else if flowManager.isUtteranceRecording {
                Text(AppL10n.string("home.flow.recording"))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            } else if flowManager.isUtteranceProcessing {
                Text(AppL10n.string("home.flow.processing"))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            } else if flowManager.isActive,
               FlowSessionBridge.isHostReady(),
               let expires = flowManager.sessionExpiresAt {
                Text(AppL10n.string("home.flow.label"))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textPrimary)
                Text("·")
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                Text(AppL10n.string(serviceSourceLabelKey))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
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

            if !serviceReadiness.canDictate {
                // The account card offers the setup paths.
                EmptyView()
            } else if canRetryPiP {
                Button {
                    flowManager.retryPiPRecovery()
                } label: {
                    Text(AppL10n.string("home.flow.retry"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
                Button {
                    flowManager.endSession()
                } label: {
                    Text(AppL10n.string("home.flow.endShort"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            } else if canEndFlowSession {
                Button {
                    flowManager.endSession()
                } label: {
                    Text(AppL10n.string("home.flow.endShort"))
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
                    Text(AppL10n.string("home.flow.startShort"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.leading, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 6)
        .background(palette.textPrimary.opacity(0.06), in: Capsule())
        .animation(Motion.soft, value: flowManager.isActive)
        .accessibilityIdentifier("home.flow.statusCapsule")
    }

    private var serviceSourceLabelKey: String {
        switch serviceReadiness {
        case .credits: return "home.flow.source.credits"
        case .ownKey: return "home.flow.source.ownKey"
        case .dictationOnly, .unavailable: return "home.flow.source.dictationOnly"
        }
    }

    private var flowStatusColor: Color {
        if !serviceReadiness.canDictate { return palette.warning }
        if flowManager.isUtteranceRecording { return palette.accent }
        if flowManager.isUtteranceProcessing { return palette.accent }
        if case .failed = flowManager.pipLifecycleState { return palette.warning }
        if case .waitingForForeground = flowManager.pipLifecycleState { return palette.warning }
        if flowManager.isActive, FlowSessionBridge.isHostReady() { return palette.accent }
        if flowManager.isStarting { return palette.accent }
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
