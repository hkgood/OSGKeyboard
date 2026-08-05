// OSGKeyboardApp.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared
import OSGKeyboardHostSupport

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
        // Deliberately do NOT prepare Custom LM here. App launch already sits
        // near ~150 MB RSS in Debug; compiling CLM during onboarding races the
        // keyboard extension and gets the host jetsammed (signal 9). Warmup
        // runs from MainAppRoot only after onboarding completes.
        OSGDiag.log("OSGKeyboardApp.init \(OSGDiag.memoryTag())", category: "flow")
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
