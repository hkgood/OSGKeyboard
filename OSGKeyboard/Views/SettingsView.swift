// SettingsView.swift
// OSGKeyboard · Main App
//
// Settings home: daily controls + summary navigation into secondary
// pages for low-frequency configuration.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI

enum SettingsPresentation {
    case tab
    case sheet
}

/// Routes pushed from Settings home. Value-based navigation keeps
/// destinations out of the root view tree until push — important so
/// `hidesTabBarWhenPushed()` preferences do not leak onto the home
/// screen (and so we avoid NavigationLink + `dismiss` freeze cycles).
private enum SettingsRoute: Hashable {
    case account
    case speechRecognition
    case microphonePriority
    case textPolish
    case general
    case aiAgent
    case clipboard
    case about
}

struct SettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @EnvironmentObject private var accountSession: AccountSessionCoordinator

    @ObservedObject var config = ProviderConfig.shared

    let presentation: SettingsPresentation

    init(presentation: SettingsPresentation = .sheet) {
        self.presentation = presentation
    }

    // Dynamic locale list loaded from SFSpeechRecognizer on first appear.
    @State private var dynamicLocales: [(id: String, onDevice: Bool)] = []
    @State private var showResetConfirmation = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    CardPageContent {
                        accountEntrySection
                        dailySection
                        transcriptionAndPolishSection
                        if presentation == .tab {
                            moreEntriesSection
                        }
                    }
                    .modifier(SettingsScrollBottomPadding(presentation: presentation))
                }
            }
            .background(palette.background)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("settings.reset.confirm")
                    .confirmationDialog(
                        "settings.reset.title",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("common.reset", role: .destructive) {
                            config.reset()
                            SpeechHistoryStore.shared.clearAll()
                        }
                        Button("common.cancel", role: .cancel) {}
                    } message: {
                        Text("settings.reset.message")
                    }
                }
                if presentation == .sheet {
                    ToolbarItem(placement: .confirmationAction) {
                        // Keep `dismiss` off the Settings root — pairing it
                        // with NavigationLink / stack pushes can freeze UI.
                        SettingsSheetDismissButton()
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .task { await loadDynamicLocales() }
            .onAppear {
                consumeClipboardDeepLinkIfNeeded()
                consumeAccountDeepLinkIfNeeded()
                Task { await accountSession.refreshAccountData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .osgOpenSettingsDeepLink)) { _ in
                consumeClipboardDeepLinkIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .osgOpenAccountDeepLink)) { _ in
                consumeAccountDeepLinkIfNeeded()
            }
        }
    }

    private func consumeClipboardDeepLinkIfNeeded() {
        guard SettingsDeepLink.consumePending() == .clipboard else { return }
        if !path.isEmpty {
            path = NavigationPath()
        }
        path.append(SettingsRoute.clipboard)
    }

    private func consumeAccountDeepLinkIfNeeded() {
        guard accountSession.consumeAccountCenterPresentation() else { return }
        if !path.isEmpty {
            path = NavigationPath()
        }
        path.append(SettingsRoute.account)
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .account:
            AccountCenterView()
        case .speechRecognition:
            SpeechRecognitionSettingsView(config: config)
        case .microphonePriority:
            MicrophonePrioritySettingsView()
        case .textPolish:
            TextPolishSettingsView(config: config)
        case .general:
            GeneralSettingsView(config: config)
        case .aiAgent:
            AIAgentSettingsView(config: config)
        case .clipboard:
            ClipboardSettingsView(config: config)
        case .about:
            AboutSettingsView(config: config)
        }
    }

    // MARK: - Optional account

    private var accountEntrySection: some View {
        CardSection("account.settings.section") {
            VStack(spacing: Spacing.sm) {
                Group {
                    switch accountSession.sessionPhase {
                    case .restoring:
                        HStack(spacing: Spacing.sm) {
                            ProgressView()
                                .tint(palette.accent)
                            Text("account.settings.restoring")
                                .font(TypeStyle.body)
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                        }
                        .settingsListRow()
                    case .signedOut:
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text("account.signedOut.title")
                                    .font(TypeStyle.headline)
                                    .foregroundStyle(palette.textPrimary)
                                Text("account.signedOut.body")
                                    .font(TypeStyle.footnote)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            AccountAppleAuthorizationButton(purpose: .signIn)
                                .disabled(accountSession.operation != nil)
                        }
                        .padding(Spacing.md)
                    case let .signedIn(session):
                        Button {
                            path.append(SettingsRoute.account)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                AccountAvatarView(
                                    accountID: session.accountID,
                                    displayName: session.displayName,
                                    size: 44
                                )

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(
                                        session.displayName
                                            ?? AppL10n.string(
                                                "account.profile.fallbackName",
                                                language: config.uiLanguage
                                            )
                                    )
                                        .font(TypeStyle.bodyEmph)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(accountSettingsSubtitle)
                                        .font(TypeStyle.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }

                                Spacer(minLength: Spacing.xs)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .settingsListRow()
                            .contentShape(Rectangle())
                            .accessibilityLabel(
                                Text(
                                    "\(Text("account.settings.signedIn")) \(session.accountID.uuidString)"
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .surfaceCard()

                if accountSession.isSignedIn {
                    accountRewardsEntrySection
                }
            }
        }
    }

    private var accountRewardsEntrySection: some View {
        VStack(spacing: 0) {
            switch accountSession.snapshotPhase {
            case let .loaded(snapshot):
                let totalCredits = creditTotal(snapshot)
                Button {
                    path.append(SettingsRoute.account)
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .top, spacing: Spacing.md) {
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(creditRemainingText(snapshot.credits.balance))
                                    .font(TypeStyle.title3.monospacedDigit())
                                    .foregroundStyle(palette.textPrimary)
                                Text("account.credits.balance")
                                    .font(TypeStyle.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }

                            Spacer(minLength: Spacing.xs)

                            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                                Text(creditUsedText(snapshot.credits.usedCredits))
                                Text(creditTotalText(totalCredits))
                            }
                            .font(TypeStyle.caption)
                            .monospacedDigit()
                            .foregroundStyle(palette.textSecondary)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textTertiary)
                                .frame(minWidth: 32, minHeight: 32)
                                .accessibilityHidden(true)
                        }

                        AccountCreditProgress(
                            remaining: snapshot.credits.balance,
                            used: snapshot.credits.usedCredits,
                            showsLabels: false
                        )
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(Spacing.md)
            case .failed:
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("account.error.load")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                    Button("account.retry") {
                        Task { await accountSession.refreshAccountData(force: true) }
                    }
                    .font(TypeStyle.bodyEmph)
                    .foregroundStyle(palette.accent)
                }
                .padding(Spacing.md)
            case .idle, .loading:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .tint(palette.accent)
                    Text("account.loading.center")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textSecondary)
                }
                .settingsListRow()
            }

            Divider().background(palette.divider)
            AccountReferralLinkView(viewModel: accountSession.referralProfile)
        }
        .surfaceCard()
    }

    private func creditTotal(_ snapshot: AccountCenterSnapshot) -> Int64 {
        let remaining = max(snapshot.credits.balance, 0)
        let used = max(snapshot.credits.usedCredits, 0)
        let (total, overflow) = remaining.addingReportingOverflow(used)
        return overflow ? Int64.max : total
    }

    private func creditRemainingText(_ remaining: Int64) -> String {
        AppL10n.format(
            "account.credits.remainingCompact",
            language: config.uiLanguage,
            max(remaining, 0).formatted(.number.grouping(.automatic))
        )
    }

    private func creditUsedText(_ used: Int64) -> String {
        AppL10n.format(
            "account.credits.usedCompact",
            language: config.uiLanguage,
            max(used, 0).formatted(.number.grouping(.automatic))
        )
    }

    private func creditTotalText(_ total: Int64) -> String {
        AppL10n.format(
            "account.credits.totalValueCompact",
            language: config.uiLanguage,
            total.formatted(.number.grouping(.automatic))
        )
    }

    private var accountSettingsSubtitle: String {
        switch accountSession.sessionPhase {
        case .restoring:
            return AppL10n.string("account.settings.restoring", language: config.uiLanguage)
        case .signedOut:
            return AppL10n.string("account.settings.signedOut", language: config.uiLanguage)
        case .signedIn:
            return AppL10n.string("account.settings.signedIn", language: config.uiLanguage)
        }
    }

    // MARK: - Daily (high-frequency)

    private var dailySection: some View {
        CardSection("settings.daily.title") {
            VStack(spacing: 0) {
                settingsRouteButton(.general, title: "settings.general.title")

                Divider().background(palette.divider)

                settingsRouteButton(
                    .aiAgent,
                    title: "settings.aiAgent.title",
                    subtitle: SharedL10n.string(
                        config.aiResponseLength.labelKey,
                        language: config.uiLanguage
                    )
                )

                Divider().background(palette.divider)

                settingsRouteButton(
                    .clipboard,
                    title: "settings.clipboard.title",
                    subtitle: clipboardSettingsSubtitle
                )

                Divider().background(palette.divider)

                LocalePickerRow(
                    locales: effectiveLocales,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )

                Divider().background(palette.divider)

                PolishIntensityPickerRow(config: config)

                Divider().background(palette.divider)

                TranslationPickerRow(config: config, isVisible: config.isTranslationRowVisible)
            }
            .surfaceCard()
        }
    }

    // MARK: - Transcription & polish

    private var transcriptionAndPolishSection: some View {
        EnginePickerSection(config: config) {
            Divider().background(palette.divider)

            settingsRouteButton(
                .speechRecognition,
                title: "settings.speechRecognition.title",
                subtitle: SettingsConfigSummary.speechRecognition(config: config)
            )

            Divider().background(palette.divider)

            settingsRouteButton(
                .microphonePriority,
                title: "settings.microphonePriority.title",
                subtitle: AppL10n.string(
                    "settings.microphonePriority.subtitle",
                    language: config.uiLanguage
                )
            )

            Divider().background(palette.divider)

            settingsRouteButton(
                .textPolish,
                title: "settings.textPolish.title",
                subtitle: SettingsConfigSummary.textPolish(config: config)
            )
        }
    }

    // MARK: - About

    private var moreEntriesSection: some View {
        VStack(spacing: 0) {
            settingsRouteButton(.about, title: "settings.about.title")

            Divider().background(palette.divider)

            // Opens the remote release-notes sheet (same as post-upgrade prompt).
            SettingsVersionRow()
        }
        .surfaceCard()
    }

    private var clipboardSettingsSubtitle: String {
        if config.clipboardHistoryEnabled {
            return AppL10n.string("settings.clipboard.subtitle.on", language: config.uiLanguage)
        }
        return AppL10n.string("settings.clipboard.subtitle.off", language: config.uiLanguage)
    }

    private func settingsRouteButton(
        _ route: SettingsRoute,
        title: LocalizedStringKey,
        subtitle: String? = nil
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            SettingsNavigationRow(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Locale helpers

    /// Falls back to a static list while dynamic locales are loading.
    private var effectiveLocales: [(id: String, onDevice: Bool)] {
        dynamicLocales.isEmpty ? SettingsASRLocales.staticFallback : dynamicLocales
    }

    private func loadDynamicLocales() async {
        dynamicLocales = await SettingsASRLocales.loadDynamic()
    }
}

private struct AccountReferralLinkView: View {
    @Environment(\.themePalette) private var palette
    @ObservedObject var viewModel: ReferralProfileViewModel

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:
                retryRow(
                    messageKey: "account.referral.loadLink",
                    actionKey: "account.referral.loadLink"
                )
            case .loading:
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(palette.accent)
                    Text("account.referral.loadingLink")
                        .font(TypeStyle.footnote)
                        .foregroundStyle(palette.textSecondary)
                }
            case .failed(let messageKey):
                retryRow(messageKey: messageKey, actionKey: "account.retry")
            case .loaded(let profile):
                loadedContent(profile)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("account.referral.profile")
    }

    private func loadedContent(_ profile: ReferralProfile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.md) {
                Text("account.referral.equalRewardDescription")
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.xs)
                AccountInvitationButton(invitationURL: profile.code.inviteURL)
            }

            if viewModel.isRefreshing {
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("account.referral.refreshingLink")
                }
                .font(TypeStyle.caption)
                .foregroundStyle(palette.textTertiary)
            } else if let refreshErrorKey = viewModel.refreshErrorKey {
                retryRow(messageKey: refreshErrorKey, actionKey: "account.retry")
            }
        }
    }

    private func retryRow(
        messageKey: String,
        actionKey: LocalizedStringKey
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Text(LocalizedStringKey(messageKey))
                .font(TypeStyle.footnote)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: Spacing.xs)
            Button(actionKey) {
                Task { await viewModel.refresh() }
            }
            .font(TypeStyle.bodyEmph)
            .foregroundStyle(palette.accent)
        }
    }
}

// MARK: - Sheet dismiss (isolated from Settings root)

private struct SettingsSheetDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("common.done") { dismiss() }
    }
}

// MARK: - Tab dock bottom padding (tab root only)

private struct SettingsScrollBottomPadding: ViewModifier {
    let presentation: SettingsPresentation

    func body(content: Content) -> some View {
        if presentation == .tab {
            content.tabBarScrollBottomPadding()
        } else {
            content.padding(.bottom, Spacing.lg)
        }
    }
}
