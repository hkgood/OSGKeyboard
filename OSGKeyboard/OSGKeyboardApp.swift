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
        // Register backend-specific ASR providers. The shared
        // framework ships a built-in SpeechAnalyzer provider; we
        // install the Qwen3-ASR provider here because linking
        // `Qwen3ASR` pulls in mlx-swift, which the keyboard
        // extension's `APPLICATION_EXTENSION_API_ONLY` build would
        // refuse. Doing it in the host app's `init` keeps the heavy
        // dependency localised.
        ASRServiceFactory.providers[.qwen3ASR] = Qwen3ASRServiceProvider()
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
                    if config.isLocalEngine {
                        OnDeviceModelWarmup.shared.warmUpIfNeeded()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                flowManager.handleScenePhase(phase)
                guard phase == .active, AppGroup.isAvailable, config.hasCompletedOnboarding else { return }
                if config.isLocalEngine {
                    OnDeviceModelWarmup.shared.ensureReadyAfterBackground()
                }
                if flowManager.isActive {
                    flowManager.extendSession()
                } else {
                    flowManager.autoStartIfNeeded()
                }
            }
        }
    }
}
