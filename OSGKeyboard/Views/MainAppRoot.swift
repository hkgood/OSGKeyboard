// MainAppRoot.swift
// OSGKeyboard · Main App
//
// Host-app shell that owns `ProviderConfig` and `FlowSessionManager`.
// Only constructed when `AppGroup.isAvailable` so the error path never
// touches App Group–backed singletons.

import OSGKeyboardHostSupport
import OSGKeyboardShared
import SwiftUI
import UIKit

enum AnalyticsFirstOpenAttribution {
    static let ordinaryLaunch: AnalyticsAcquisitionChannel = .appStoreOrganic

    static func trustedChannel(for url: URL) -> AnalyticsAcquisitionChannel? {
        ReferralUniversalLink.code(from: url) == nil ? nil : .referral
    }
}

/// One native Reminders export handed off from the keyboard. Identifiable so a
/// repeated skill run with the same titles still re-triggers the writer.
struct ReminderDraft: Identifiable, Equatable {
    let id = UUID()
    let titles: [String]
}

/// One native Calendar export handed off from the keyboard. `lines` are the
/// canonical `start|end|title|location` entries `AIEventExporter` decodes.
struct EventDraft: Identifiable, Equatable {
    let id = UUID()
    let lines: [String]
}

struct MainAppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.themePalette) private var palette: ThemePalette

    // Singleton is owned by `ProviderConfig.shared`, not by this view —
    // `@ObservedObject` keeps subscriptions correct across Settings replay.
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var releaseNotes = ReleaseNotesController.shared
    @ObservedObject private var analytics = AnalyticsHostService.shared
    @StateObject private var flowManager: FlowSessionManager
    @StateObject private var accountSession: AccountSessionCoordinator
    @State private var clmWarmupTask: Task<Void, Never>?
    @State private var rimeStartupTask: Task<Void, Never>?
    @State private var firstOpenAcquisitionChannel =
        AnalyticsFirstOpenAttribution.ordinaryLaunch
    @State private var newContactDraft: NewContactDraft?
    @State private var reminderDraft: ReminderDraft?
    @State private var reminderOutcome: AIReminderExporter.Outcome?
    @State private var eventDraft: EventDraft?
    @State private var eventOutcome: AIEventExporter.Outcome?

    init(accountDependencies: AccountDependencies? = nil) {
        let resolvedDependencies = accountDependencies ?? LiveAccountDependencyFactory.make()
        let analytics = AnalyticsHostService.shared
        _flowManager = StateObject(
            wrappedValue: FlowSessionManager(analyticsClient: analytics.client)
        )
        _accountSession = StateObject(
            wrappedValue: AccountSessionCoordinator(
                dependencies: resolvedDependencies,
                analyticsClient: analytics.client,
                onAccountAuthenticated: { accountID in
                    AppGroupStore().setManagedGatewayAccountSessionAvailable(true)
                    await analytics.observeAuthenticatedAccount(accountID)
                },
                onAccountSignedOut: {
                    // Revoke the local choice before exposing signed-out UI.
                    // BYOK then remains the only possible AI execution path.
                    AppGroupStore().setManagedGatewayAccountSessionAvailable(false)
                    let config = ProviderConfig.shared
                    if config.credentialSource != .byok {
                        config.credentialSource = .byok
                    }
                },
                onAccountDeleted: {
                    await analytics.handleAccountDeletion()
                }
            )
        )
    }

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()
            mainContent
        }
        .environment(\.locale, config.uiLanguage.swiftUILocale)
        .environmentObject(flowManager)
        .environmentObject(accountSession)
        .environmentObject(analytics)
        .alert(
            AppL10n.string("account.error.title"),
            isPresented: accountOperationErrorBinding
        ) {
            Button(AppL10n.string("common.done")) {
                accountSession.dismissOperationError()
            }
        } message: {
            if let key = accountSession.operationErrorKey {
                Text(AppL10n.string(key))
            }
        }
        .background {
            FlowPiPHostView { view in
                flowManager.attachPiPHostView(view)
            }
            // Keep a small but real layer in the window hierarchy for PiP.
            .frame(width: 64, height: 36)
            .opacity(0.02)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $releaseNotes.isPresented, onDismiss: {
            // Auto-present and Settings entry both count as acknowledged.
            ReleaseNotesStore.markCurrentVersionSeen()
        }) {
            // Pass language explicitly; sheet chrome uses AppL10n (in-app override).
            ReleaseNotesSheet(language: config.uiLanguage)
                .environment(\.locale, config.uiLanguage.swiftUILocale)
        }
        .sheet(item: $newContactDraft) { draft in
            NewContactSheet(phoneNumber: draft.phoneNumber) {
                newContactDraft = nil
            }
        }
        .task(id: reminderDraft?.id) {
            guard let draft = reminderDraft else { return }
            let outcome = await AIReminderExporter.add(titles: draft.titles)
            reminderDraft = nil
            reminderOutcome = outcome
        }
        .alert(
            AppL10n.string("skills.reminders.resultTitle"),
            isPresented: reminderOutcomeBinding
        ) {
            if reminderOutcome == .accessDenied {
                Button(AppL10n.string("skills.reminders.openSettings")) {
                    reminderOutcome = nil
                    openSystemSettings()
                }
                Button(AppL10n.string("common.done"), role: .cancel) {
                    reminderOutcome = nil
                }
            } else {
                Button(AppL10n.string("common.done")) {
                    reminderOutcome = nil
                }
            }
        } message: {
            Text(AppL10n.string(reminderOutcomeMessage))
        }
        .task(id: eventDraft?.id) {
            guard let draft = eventDraft else { return }
            let outcome = await AIEventExporter.add(lines: draft.lines)
            eventDraft = nil
            eventOutcome = outcome
        }
        .alert(
            AppL10n.string("skills.events.resultTitle"),
            isPresented: eventOutcomeBinding
        ) {
            if eventOutcome == .accessDenied {
                Button(AppL10n.string("skills.events.openSettings")) {
                    eventOutcome = nil
                    openSystemSettings()
                }
                Button(AppL10n.string("common.done"), role: .cancel) {
                    eventOutcome = nil
                }
            } else {
                Button(AppL10n.string("common.done")) {
                    eventOutcome = nil
                }
            }
        } message: {
            Text(AppL10n.string(eventOutcomeMessage))
        }
        .onAppear {
            flowManager.setAppForeground(scenePhase == .active)
            // Register the URL handler BEFORE the foreground auto-start.
            // Registering flushes any URL buffered during a cold launch (the
            // keyboard → app `startflow` handoff arrives via the scene
            // delegate before this view is on screen), so a cold start takes
            // the cold-start path first and `activateOnForeground()`'s plain
            // start then no-ops on the isStarting guard — instead of two
            // start bodies racing each other on the main actor.
            AppOpenURLRouter.shared.register { url in
                handleIncomingURL(url)
            }
            analytics.prepare(
                firstOpenAcquisitionChannel: firstOpenAcquisitionChannel
            )
            if scenePhase == .active {
                analytics.appDidBecomeActive()
            }
            OSGDiag.log(
                "MainAppRoot.onAppear scene=\(String(describing: scenePhase)) "
                    + "onboarding=\(config.hasCompletedOnboarding) \(OSGDiag.memoryTag())",
                category: "flow"
            )
            AppCloudSync.shared.startObservingExternalChanges()
            if scenePhase == .active {
                refreshOfficialSkillCatalog(reason: "MainAppRoot.onAppear")
            }

            // Heavy work (Flow / CLM / Rime) only after onboarding. Doing it
            // earlier jetsams the host (~150 MB+) and the keyboard dies with it.
            if config.hasCompletedOnboarding {
                // Rime deployment is host-only and idempotent. Run it
                // immediately when missing so returning users never have to
                // wait for an opportunistic background warmup. The startup
                // scheduler yields the first frame before beginning deployment.
                if scenePhase == .active {
                    activateForegroundServices(reason: "MainAppRoot.onAppear")
                    AIHintRefreshService.refreshIfNeeded(reason: "MainAppRoot.onAppear")
                    if newContactDraft == nil {
                        releaseNotes.presentIfNeeded(onboardingCompleted: true)
                    }
                } else {
                    OSGDiag.log(
                        "MainAppRoot.onAppear defer foreground services scene="
                            + "\(String(describing: scenePhase))",
                        category: "flow"
                    )
                }
            } else {
                OSGDiag.log(
                    "MainAppRoot.onAppear skip Flow/CLM/Rime (onboarding incomplete)",
                    category: "flow"
                )
            }
        }
        .task {
            await accountSession.restoreIfNeeded()
            if scenePhase == .active {
                await accountSession.validateAppleCredentialState()
            }
            config.reloadFromPersistedStorage()
            // Sweep after the session is restored so the upload carries a
            // bearer token. No-op outside internal builds. This is the retry
            // path: MetricKit itself triggers an upload the moment a payload
            // arrives, but a send that failed then only gets another chance
            // here, on a later launch.
            await InternalDiagnosticsUploader.shared.uploadPendingReports()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            config.reloadFromPersistedStorage()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .managedCreditsMayHaveChanged)
        ) { _ in
            Task {
                await accountSession.refreshAccountData(force: true)
            }
        }
        .onChange(of: config.hasCompletedOnboarding) { _, done in
            if done {
                // Deploy now rather than via warmup: the user just finished
                // setup, is still in the app, and has not started using the
                // keyboard yet — so there is nothing to race for memory. This
                // also covers users who skipped the keyboard page entirely.
                if scenePhase == .active {
                    activateForegroundServices(reason: "onboardingCompleted")
                    AIHintRefreshService.refreshIfNeeded(reason: "onboardingCompleted")
                    if newContactDraft == nil {
                        releaseNotes.presentIfNeeded(onboardingCompleted: true)
                    }
                }
                if accountSession.shouldPresentAccountCenter {
                    Task { @MainActor in
                        // Let MainTabView enter the hierarchy before publishing.
                        await Task.yield()
                        NotificationCenter.default.post(name: .osgOpenAccountDeepLink, object: nil)
                    }
                }
            }
        }
        .onChange(of: config.engineMode) { _, _ in
            guard config.credentialSource == .managed,
                  accountSession.isSignedIn else { return }
            Task { _ = await accountSession.prepareManagedGateway() }
        }
        .onChange(of: scenePhase) { _, phase in
            flowManager.handleScenePhase(phase)
            if phase == .active {
                analytics.appDidBecomeActive()
            } else if phase == .inactive {
                analytics.appWillResignActive()
            } else if phase == .background {
                analytics.appDidEnterBackground()
            }
            guard phase == .active else {
                clmWarmupTask?.cancel()
                clmWarmupTask = nil
                rimeStartupTask?.cancel()
                rimeStartupTask = nil
                FlowSessionBridge.setHostHeavy(false)
                return
            }
            refreshOfficialSkillCatalog(reason: "scenePhase.active")
            Task {
                // A protected Keychain can be temporarily unavailable during
                // launch. The coordinator no-ops after a terminal restore, so
                // this only retries a previously interrupted attempt.
                await accountSession.restoreIfNeeded()
                await accountSession.validateAppleCredentialState()
            }
            if config.hasCompletedOnboarding {
                activateForegroundServices(reason: "scenePhase.active")
                AIHintRefreshService.refreshIfNeeded(reason: "scenePhase.active")
                if newContactDraft == nil {
                    releaseNotes.presentIfNeeded(onboardingCompleted: true)
                }
            }
            Task { await AppCloudSync.shared.pullAllIfEnabled() }
        }
    }

    private var accountOperationErrorBinding: Binding<Bool> {
        Binding(
            get: { accountSession.operationErrorKey != nil },
            set: { isPresented in
                if !isPresented {
                    accountSession.dismissOperationError()
                }
            }
        )
    }

    private var reminderOutcomeBinding: Binding<Bool> {
        Binding(
            get: { reminderOutcome != nil },
            set: { isPresented in
                if !isPresented { reminderOutcome = nil }
            }
        )
    }

    private var reminderOutcomeMessage: String {
        switch reminderOutcome {
        case .created:
            return "skills.reminders.resultSuccess"
        case .accessDenied:
            return "skills.reminders.resultDenied"
        case .failed, .none:
            return "skills.reminders.resultFailed"
        }
    }

    private var eventOutcomeBinding: Binding<Bool> {
        Binding(
            get: { eventOutcome != nil },
            set: { isPresented in
                if !isPresented { eventOutcome = nil }
            }
        )
    }

    private var eventOutcomeMessage: String {
        switch eventOutcome {
        case .created:
            return "skills.events.resultSuccess"
        case .accessDenied:
            return "skills.events.resultDenied"
        case .failed, .none:
            return "skills.events.resultFailed"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshOfficialSkillCatalog(reason: String) {
        Task {
            let outcome = await OfficialSkillCatalogRefreshService.shared.refreshIfNeeded(
                reason: reason
            )
            if outcome.didUpdateCache {
                AIAgentSkillLayoutStore.shared.reload()
            }
        }
    }

    /// Starts foreground-only services once per active transition. Rime yields
    /// the first frame; Flow and CLM keep their existing lazy-heavy-work rules.
    private func activateForegroundServices(reason: String) {
        scheduleRimeDeployment(reason: reason)
        // Automatically arm the low-profile PiP on every host open.
        // Capture/ASR remain lazy and start only on an actual mic press.
        flowManager.activateOnForeground(reason: reason)
        // Retry deferred CLM after a jetsam-prone launch.
        scheduleCLMWarmup(reason: reason)
        releaseNotes.presentIfNeeded(onboardingCompleted: true)
    }

    /// Rime remains startup-owned, but PiP gets exclusive use of the launch
    /// critical path before deployment claims CPU, file I/O and memory.
    private func scheduleRimeDeployment(reason: String) {
        rimeStartupTask?.cancel()
        guard !RimeResourceInstaller.isReady else {
            RimeDeploymentController.shared.refreshStatus()
            rimeStartupTask = nil
            return
        }

        OSGDiag.log(
            "rime startup scheduled reason=\(reason) afterFlowStart \(OSGDiag.memoryTag())",
            category: "flow"
        )
        rimeStartupTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, scenePhase == .active else { return }

            // A normal cold PiP start settles in under one second. Keep a
            // bounded ceiling so an unavailable PiP never blocks typing
            // resource installation for the rest of the foreground session.
            let flowDeadline = Date().addingTimeInterval(12)
            while flowManager.shouldDeferHostHeavyWork, Date() < flowDeadline {
                guard !Task.isCancelled, scenePhase == .active else { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled, scenePhase == .active else { return }
            RimeDeploymentController.shared.deployNow(reason: reason)
            rimeStartupTask = nil
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if config.hasCompletedOnboarding, !Self.forcesOnboarding {
            MainTabView()
                .id("main-\(config.uiLanguage.rawValue)")
        } else {
            OnboardingExperienceView(config: config)
                .id("onboarding-\(config.uiLanguage.rawValue)")
        }
    }

    /// DEBUG-only: replay the first-run experience without wiping data — used to
    /// preview onboarding on a device that already finished setup. Pass
    /// `--force-onboarding` to start from the top, or `--oobe-preview=reply`
    /// (voice / translate / reply / ask-ai / login / complete) to jump straight
    /// to a specific step. Both are set in the Xcode scheme's launch arguments.
    private static var forcesOnboarding: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--force-onboarding")
            || arguments.contains(where: { $0.hasPrefix("--oobe-preview=") })
        #else
        return false
        #endif
    }

    /// Delayed host CLM warmup. Never parallel with ASR.
    /// ASR warms on first mic press (`FlowSessionManager.beginUtterance`).
    ///
    /// Intentionally delayed: warming CLM on `onAppear` kept the host at
    /// ~175 MB while the user switched to the keyboard. Rime is excluded from
    /// this opportunistic path because missing typing resources block users.
    private func scheduleCLMWarmup(reason: String) {
        OSGDiag.log(
            "clmWarmup scheduled reason=\(reason) delay=45s \(OSGDiag.memoryTag())",
            category: "flow"
        )
        clmWarmupTask?.cancel()
        clmWarmupTask = Task { @MainActor in
            // Let the user leave the host / cold-start the keyboard first.
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            guard scenePhase == .active else {
                OSGDiag.log(
                    "clmWarmup skip reason=notActive \(OSGDiag.memoryTag())",
                    category: "flow"
                )
                return
            }
            guard !flowManager.shouldDeferHostHeavyWork else {
                OSGDiag.log(
                    "clmWarmup skip reason=flowBusy \(OSGDiag.memoryTag())",
                    category: "flow"
                )
                return
            }

            await AppCloudSync.shared.pullAllIfEnabled()

            guard HostMemoryBudget.gate("clm.prepare", category: "asr") else { return }
            CustomLanguageModelManager.shared.prepareInBackgroundIfNeeded()
            OSGDiag.log("clm.prepare scheduled \(OSGDiag.memoryTag())", category: "asr")
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if accountSession.handleIncomingURL(url) {
            firstOpenAcquisitionChannel =
                AnalyticsFirstOpenAttribution.trustedChannel(for: url)
                ?? AnalyticsFirstOpenAttribution.ordinaryLaunch
            NotificationCenter.default.post(name: .osgOpenAccountDeepLink, object: nil)
            return
        }

        guard url.scheme == "osgkeyboard" else { return }
        switch url.host {
        case "startflow":
            flowManager.startSession(coldStart: true, reason: "url.startflow")
        case "skill":
            if url.path.contains("shortcut-result") {
                AIAgentShortcutRunner.logShortcutCallback(url)
            } else if url.path.contains("run") {
                AIAgentShortcutRunner.runPendingIfNeeded(
                    onReminders: { titles in
                        reminderDraft = ReminderDraft(titles: titles)
                    },
                    onEvents: { lines in
                        eventDraft = EventDraft(lines: lines)
                    }
                )
            }
        case "deployrime":
            // The keyboard sends the user here precisely because typing
            // resources are missing — deploy without waiting for warmup.
            RimeDeploymentController.shared.deployNow(reason: "url.deployrime")
        case "settings":
            // Path may be `settings/clipboard` (host = settings, path = /clipboard).
            if url.path.contains("clipboard") {
                SettingsDeepLink.setPending(.clipboard)
            }
            NotificationCenter.default.post(name: .osgOpenSettingsDeepLink, object: nil)
        case "contact":
            guard url.path.contains("new"),
                  let payload = AppGroupStore().consumePendingContactCreation() else {
                return
            }
            releaseNotes.isPresented = false
            Task { @MainActor in
                await Task.yield()
                newContactDraft = NewContactDraft(phoneNumber: payload.phoneNumber)
            }
        #if DEBUG
        case "seed-demo":
            DemoDataSeeder.seedRichPlaceholderData()
            config.reloadFromPersistedStorage()
        #endif
        default:
            break
        }
    }
}

#if DEBUG
struct EditPagerUITestHarness: View {
    @State private var selectedPage: Int? = 0

    var body: some View {
        VStack(spacing: 20) {
            ZStack(alignment: .bottom) {
                EditTextPager(
                    originalTitle: "Original",
                    originalText: "ORIGINAL_PAGE_TOKEN",
                    editedTitle: "Edited",
                    editedText: "EDITED_PAGE_TOKEN",
                    contentBottomInset: 30,
                    selectedPage: $selectedPage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Color.clear
                    .frame(height: 30)
                    .allowsHitTesting(false)
            }
            .frame(height: 220)
            .accessibilityIdentifier("edit.pager.swipeArea")

            Text(selectedPage == 1 ? "EDITED_ACTIVE" : "ORIGINAL_ACTIVE")
                .accessibilityIdentifier("edit.pager.activePage")
        }
        .padding()
        .environment(\.themePalette, Palette.light)
    }
}
#endif
