// OSGKeyboardApp.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

@main
struct OSGKeyboardApp: App {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var config = ProviderConfig.shared
    @StateObject private var dictationCoordinator = DictationSessionCoordinator()
    @StateObject private var flowManager = FlowSessionManager()

    init() {
        MaterialIconsFont.registerIfNeeded()
        #if DEBUG
        // Reset onboarding on each launch so guide screens can be reviewed while iterating UI.
        ProviderConfig.shared.hasCompletedOnboarding = false
        ProviderConfig.shared.onboardingPage = 0
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                if AppGroup.isAvailable {
                    if config.hasCompletedOnboarding {
                        MainTabView()
                    } else {
                        OnboardingView(config: config)
                    }
                } else {
                    AppGroupErrorView()
                }
            }
            .environmentObject(flowManager)
            .onOpenURL { url in
                guard url.scheme == "osgkeyboard" else { return }
                switch url.host {
                case "dictate":
                    dictationCoordinator.present()
                case "startflow":
                    flowManager.startSession()
                default:
                    break
                }
            }
            .fullScreenCover(isPresented: $dictationCoordinator.isPresenting) {
                DictationCaptureView(
                    config: config,
                    coordinator: dictationCoordinator
                )
            }
            .onChange(of: config.hasCompletedOnboarding) { _, done in
                if done { flowManager.autoStartIfNeeded() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, AppGroup.isAvailable, config.hasCompletedOnboarding else { return }
                if flowManager.isActive {
                    flowManager.extendSession()
                } else {
                    flowManager.autoStartIfNeeded()
                }
            }
        }
    }
}
