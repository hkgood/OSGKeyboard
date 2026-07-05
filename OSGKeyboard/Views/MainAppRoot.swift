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
        .onAppear {
            flowManager.setAppForeground(scenePhase == .active)
        }
        .onOpenURL { url in
            guard url.scheme == "osgkeyboard" else { return }
            switch url.host {
            case "startflow":
                flowManager.startSession()
            default:
                break
            }
        }
        .onChange(of: config.hasCompletedOnboarding) { _, done in
            if done {
                flowManager.autoStartIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            flowManager.handleScenePhase(phase)
            guard phase == .active, config.hasCompletedOnboarding else { return }
            if flowManager.isActive {
                flowManager.extendSession()
            } else {
                flowManager.autoStartIfNeeded()
            }
        }
    }
}
