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
        // v0.2.0: no backend-specific ASR provider to install here.
        // The local engine uses iOS 26 `SpeechAnalyzer` +
        // `DictationTranscriber`, which the shared framework wires
        // up directly via `ASRServiceFactory.make(...)`. The previous
        // Qwen3 CoreML backend (and its mlx-swift transitive
        // dependency) was removed in this release.
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
            .environment(\.locale, config.uiLanguage.swiftUILocale)
            .environmentObject(flowManager)
            .onAppear {
                FlowAppLifecycle.shared.setForeground(scenePhase == .active)
                flowManager.setAppForeground(scenePhase == .active)
            }
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
                if done {
                    flowManager.autoStartIfNeeded()
                    // v0.2.0: no on-device ASR weights to warm up.
                    // iOS `SpeechAnalyzer` is always ready.
                }
            }
            .onChange(of: scenePhase) { _, phase in
                flowManager.handleScenePhase(phase)
                guard phase == .active, AppGroup.isAvailable, config.hasCompletedOnboarding else { return }
                // v0.2.0: iOS `SpeechAnalyzer` is bundled with the OS
                // and needs no warm-up after a background trip.
                if flowManager.isActive {
                    flowManager.extendSession()
                } else {
                    flowManager.autoStartIfNeeded()
                }
            }
        }
    }
}
