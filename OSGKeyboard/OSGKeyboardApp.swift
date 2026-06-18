// OSGKeyboardApp.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

@main
struct OSGKeyboardApp: App {
    @StateObject private var config = ProviderConfig.shared

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                Group {
                    if config.isConfigured {
                        HomeView()
                    } else {
                        OnboardingView(config: config)
                    }
                }
            }
        }
    }
}