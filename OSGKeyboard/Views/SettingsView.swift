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
/// destination toolbar preferences do not leak onto the home screen
/// (and so we avoid NavigationLink + `dismiss` freeze cycles).
private enum SettingsRoute: Hashable {
    case account
    case speechRecognition
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
    @State private var path = NavigationPath()
    @State private var settingsScrollTarget: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollViewReader { proxy in
                    ScrollView {
                        CardPageContent {
                            accountEntrySection
                            dailySection
                            transcriptionAndPolishSection
                                .id(SettingsDeepLink.aiService.rawValue)
                            if presentation == .tab {
                                moreEntriesSection
                            }
                        }
                        .modifier(SettingsScrollBottomPadding(presentation: presentation))
                    }
                    .onChange(of: settingsScrollTarget) { _, target in
                        guard target == SettingsDeepLink.aiService.rawValue else { return }
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(Motion.soft) {
                                proxy.scrollTo(SettingsDeepLink.aiService.rawValue, anchor: .top)
                            }
                            settingsScrollTarget = nil
                        }
                    }
                }
            }
            .background(palette.background)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
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
                consumeSettingsDeepLinkIfNeeded()
                consumeAccountDeepLinkIfNeeded()
                Task { await accountSession.refreshAccountData() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .osgOpenSettingsDeepLink)) { _ in
                consumeSettingsDeepLinkIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .osgOpenAccountDeepLink)) { _ in
                consumeAccountDeepLinkIfNeeded()
            }
        }
        .navigationStackTabBarVisibility(isRoot: path.isEmpty)
    }

    private func consumeSettingsDeepLinkIfNeeded() {
        guard let link = SettingsDeepLink.consumePending() else { return }
        if !path.isEmpty {
            path = NavigationPath()
        }
        switch link {
        case .aiService:
            settingsScrollTarget = SettingsDeepLink.aiService.rawValue
        case .speechRecognition:
            path.append(SettingsRoute.speechRecognition)
        case .textPolish:
            path.append(SettingsRoute.textPolish)
        case .clipboard:
            path.append(SettingsRoute.clipboard)
        }
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
        }
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
