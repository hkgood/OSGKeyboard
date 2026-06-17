// OpenLessApp.swift
// OSGKeyboard · Main App
//
// App entry point. Switches between Onboarding and Home based on
// whether the user has configured their API key yet.

import SwiftUI
import OSGKeyboardShared

@main
struct OSGKeyboardApp: App {
    @StateObject private var config = ProviderConfig.shared

    var body: some Scene {
        WindowGroup {
            if config.isConfigured {
                HomeView()
            } else {
                OnboardingView()
            }
        }
    }
}
