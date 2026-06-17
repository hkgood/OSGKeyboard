// OSGKeyboardApp.swift
// OSGKeyboard · Main App
//
// DEBUG VERSION 2: restore real flow but instrument every step.

import SwiftUI
import OSGKeyboardShared

@main
struct OSGKeyboardApp: App {
    @StateObject private var config = ProviderConfig.shared

    init() {
        print("🔥 [OSGKeyboardApp] init()")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if config.isConfigured {
                    HomeView()
                        .onAppear { print("🔥 [OSGKeyboardApp] → HomeView appeared") }
                } else {
                    OnboardingView(config: config)
                        .onAppear { print("🔥 [OSGKeyboardApp] → OnboardingView appeared") }
                }
            }
            .onAppear { print("🔥 [OSGKeyboardApp] body appeared") }
        }
    }
}
