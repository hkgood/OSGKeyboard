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
    @State private var postOnboardingWarmupTask: Task<Void, Never>?

    var body: some View {
        Group {
            if config.hasCompletedOnboarding {
                MainTabView()
                    .id("main")
            } else {
                OnboardingView(config: config)
                    .id("onboarding")
            }
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
                // Automatically arm the low-profile PiP on every host open.
                // Capture/ASR remain lazy and start only on an actual mic press.
                flowManager.activateOnForeground(reason: "MainAppRoot.onAppear")
                schedulePostOnboardingWarmup(reason: "MainAppRoot.onAppear")
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
                schedulePostOnboardingWarmup(reason: "onboardingCompleted")
                releaseNotes.presentIfNeeded(onboardingCompleted: true)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            flowManager.handleScenePhase(phase)
            guard phase == .active else {
                postOnboardingWarmupTask?.cancel()
                postOnboardingWarmupTask = nil
                FlowSessionBridge.setHostHeavy(false)
                return
            }
            if config.hasCompletedOnboarding {
                flowManager.activateOnForeground(reason: "scenePhase.active")
                // Retry deferred Rime/CLM after a jetsam-prone launch.
                schedulePostOnboardingWarmup(reason: "scenePhase.active.retry")
                releaseNotes.presentIfNeeded(onboardingCompleted: true)
            }
            Task {
                await AppCloudSync.shared.pullAllIfEnabled()
            }
        }
    }

    /// Serial host warmup: Rime deploy → CLM. Never parallel with ASR.
    /// ASR warms on first mic press (`FlowSessionManager.beginUtterance`).
    ///
    /// Intentionally delayed: running Rime/CLM on `onAppear` kept the host at
    /// ~175 MB while the user switched to the keyboard, and the extension died
    /// before `KVC.init` (no dyld breadcrumb).
    private func schedulePostOnboardingWarmup(reason: String) {
        OSGDiag.log(
            "postOnboardingWarmup scheduled reason=\(reason) delay=45s \(OSGDiag.memoryTag())",
            category: "flow"
        )
        postOnboardingWarmupTask?.cancel()
        postOnboardingWarmupTask = Task { @MainActor in
            // Let the user leave the host / cold-start the keyboard first.
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard !Task.isCancelled else { return }
            guard scenePhase == .active else {
                OSGDiag.log(
                    "postOnboardingWarmup skip reason=notActive \(OSGDiag.memoryTag())",
                    category: "flow"
                )
                return
            }
            guard !flowManager.shouldDeferHostHeavyWork else {
                OSGDiag.log(
                    "postOnboardingWarmup skip reason=flowBusy \(OSGDiag.memoryTag())",
                    category: "flow"
                )
                return
            }

            await AppCloudSync.shared.pullAllIfEnabled()

            // hostHeavy only while heavy work runs — never leave it stuck at 1
            // just because RSS is above the soft gate (that blocked typing).
            guard HostMemoryBudget.gate("rime.installIfNeeded") else { return }

            FlowSessionBridge.setHostHeavy(true)
            defer { FlowSessionBridge.setHostHeavy(false) }

            let typingConfig = TypingInputConfiguration.shared.snapshot
            OSGDiag.log("rime.installIfNeeded begin \(OSGDiag.memoryTag())", category: "flow")
            try? await RimeResourceInstaller.shared.installIfNeeded(
                configuration: typingConfig
            )
            OSGDiag.log("rime.installIfNeeded done \(OSGDiag.memoryTag())", category: "flow")

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
