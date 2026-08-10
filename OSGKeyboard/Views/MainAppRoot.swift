// MainAppRoot.swift
// OSGKeyboard · Main App
//
// Host-app shell that owns `ProviderConfig` and `FlowSessionManager`.
// Only constructed when `AppGroup.isAvailable` so the error path never
// touches App Group–backed singletons.

import SwiftUI
import OSGKeyboardShared
import OSGKeyboardHostSupport

struct MainAppRoot: View {
    @Environment(\.scenePhase) private var scenePhase

    // Singleton is owned by `ProviderConfig.shared`, not by this view —
    // `@ObservedObject` keeps subscriptions correct across Settings replay.
    @ObservedObject private var config = ProviderConfig.shared
    @ObservedObject private var releaseNotes = ReleaseNotesController.shared
    @StateObject private var flowManager = FlowSessionManager()
    @State private var clmWarmupTask: Task<Void, Never>?

    var body: some View {
        Group {
            mainContent
        }
        .environment(\.locale, config.uiLanguage.swiftUILocale)
        .environmentObject(flowManager)
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
            OSGDiag.log(
                "MainAppRoot.onAppear scene=\(String(describing: scenePhase)) "
                    + "onboarding=\(config.hasCompletedOnboarding) \(OSGDiag.memoryTag())",
                category: "flow"
            )
            AppCloudSync.shared.startObservingExternalChanges()

            // Heavy work (Flow / CLM / Rime) only after onboarding. Doing it
            // earlier jetsams the host (~150 MB+) and the keyboard dies with it.
            if config.hasCompletedOnboarding {
                // Rime deployment is host-only and idempotent. Run it
                // immediately when missing so returning users never have to
                // wait for an opportunistic background warmup.
                RimeDeploymentController.shared.deployNow(reason: "MainAppRoot.onAppear")
                // Automatically arm the low-profile PiP on every host open.
                // Capture/ASR remain lazy and start only on an actual mic press.
                flowManager.activateOnForeground(reason: "MainAppRoot.onAppear")
                scheduleCLMWarmup(reason: "MainAppRoot.onAppear")
                releaseNotes.presentIfNeeded(onboardingCompleted: true)
            } else {
                OSGDiag.log(
                    "MainAppRoot.onAppear skip Flow/CLM/Rime (onboarding incomplete)",
                    category: "flow"
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            config.reloadFromPersistedStorage()
        }
        .onChange(of: config.hasCompletedOnboarding) { _, done in
            if done {
                flowManager.activateOnForeground(reason: "onboardingCompleted")
                // Deploy now rather than via warmup: the user just finished
                // setup, is still in the app, and has not started using the
                // keyboard yet — so there is nothing to race for memory. This
                // also covers users who skipped the keyboard page entirely.
                RimeDeploymentController.shared.deployNow(reason: "onboardingCompleted")
                scheduleCLMWarmup(reason: "onboardingCompleted")
                releaseNotes.presentIfNeeded(onboardingCompleted: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            flowManager.handleScenePhase(phase)
            guard phase == .active else {
                clmWarmupTask?.cancel()
                clmWarmupTask = nil
                FlowSessionBridge.setHostHeavy(false)
                return
            }
            if config.hasCompletedOnboarding {
                RimeDeploymentController.shared.deployNow(reason: "scenePhase.active")
                flowManager.activateOnForeground(reason: "scenePhase.active")
                // Retry deferred CLM after a jetsam-prone launch.
                scheduleCLMWarmup(reason: "scenePhase.active.retry")
                releaseNotes.presentIfNeeded(onboardingCompleted: true)
            }
            Task {
                await AppCloudSync.shared.pullAllIfEnabled()
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if config.hasCompletedOnboarding {
            MainTabView()
                .id("main")
        } else {
            OnboardingView(config: config)
                .id("onboarding")
        }
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
        guard url.scheme == "osgkeyboard" else { return }
        switch url.host {
        case "startflow":
            flowManager.startSession(coldStart: true, reason: "url.startflow")
        case "deployrime":
            // The keyboard sends the user here precisely because typing
            // resources are missing — deploy without waiting for warmup.
            RimeDeploymentController.shared.deployNow(reason: "url.deployrime")
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
