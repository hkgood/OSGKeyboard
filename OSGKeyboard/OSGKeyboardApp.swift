// OSGKeyboardApp.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

@main
struct OSGKeyboardApp: App {
    @UIApplicationDelegateAdaptor(AppURLHandler.self) private var appURLHandler

    /// App-local light / dark preference (Settings ▸ Preferences ▸ Appearance).
    @AppStorage(AppearancePreference.storageKey)
    private var appearanceRaw = AppearancePreference.system.rawValue

    private var appearance: AppearancePreference {
        AppearancePreference.fromStored(appearanceRaw)
    }

    init() {
        MaterialIconsFont.registerIfNeeded()
        if AppGroup.isAvailable {
            CustomLanguageModelManager.shared.prepareInBackgroundIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            if AppGroup.isAvailable {
                ThemedRoot {
                    MainAppRoot()
                }
                .preferredColorScheme(appearance.colorScheme)
            } else {
                ThemedRoot {
                    AppGroupErrorView()
                }
                .preferredColorScheme(appearance.colorScheme)
            }
        }
    }
}
