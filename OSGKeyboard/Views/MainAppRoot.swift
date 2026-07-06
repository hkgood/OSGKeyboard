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
                    onDismiss: { flowManager.dismissColdStartOverlay() }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: flowManager.coldStartContext != nil)
        .onAppear {
            flowManager.setAppForeground(scenePhase == .active)
            flowManager.activateOnForeground()
            PersonalDictionaryCloudSync.shared.startObservingExternalChanges()
            Task {
                await PersonalDictionaryCloudSync.shared.pullAndMergeIfEnabled()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .osgKeyboardOpenURL)) { notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            handleIncomingURL(url)
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
                await PersonalDictionaryCloudSync.shared.pullAndMergeIfEnabled()
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
