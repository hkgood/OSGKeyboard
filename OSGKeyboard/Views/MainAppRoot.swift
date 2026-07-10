// MainAppRoot.swift
// OSGKeyboard · Main App
//
// Host-app shell that owns `ProviderConfig` and `FlowSessionManager`.
// Only constructed when `AppGroup.isAvailable` so the error path never
// touches App Group–backed singletons.

import SwiftUI
import OSGKeyboardShared

struct MainAppRoot: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var config = ProviderConfig.shared
    @StateObject private var flowManager = FlowSessionManager()

    var body: some View {
        Group {
            if config.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView(config: config)
            }
        }
        .environment(\.locale, config.uiLanguage.swiftUILocale)
        .environmentObject(flowManager)
        .overlay {
            if let context = flowManager.coldStartContext {
                FlowColdStartOverlay(
                    context: context,
                    onReturnToHost: { flowManager.returnToPendingHostFromColdStart() },
                    onDismiss: { flowManager.dismissColdStartOverlay() },
                    onRetry: { flowManager.retryColdStartReadiness() },
                    onOpenSettings: { flowManager.openColdStartPermissionSettings() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flowManager.coldStartContext != nil)
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
            flowManager.activateOnForeground()
            AppCloudSync.shared.startObservingExternalChanges()
            Task {
                await AppCloudSync.shared.pullAllIfEnabled()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            config.reloadFromPersistedStorage()
        }
        .onChange(of: config.hasCompletedOnboarding) { _, done in
            if done {
                flowManager.activateOnForeground()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            flowManager.handleScenePhase(phase)
            guard phase == .active else { return }
            if config.hasCompletedOnboarding {
                flowManager.activateOnForeground()
            }
            Task {
                await AppCloudSync.shared.pullAllIfEnabled()
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == "osgkeyboard" else { return }
        switch url.host {
        case "startflow":
            flowManager.startSession(coldStart: true)
        default:
            break
        }
    }
}
