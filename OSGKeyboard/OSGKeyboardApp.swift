// OSGKeyboardApp.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

@main
struct OSGKeyboardApp: App {
    @UIApplicationDelegateAdaptor(AppURLHandler.self) private var appURLHandler

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
            } else {
                ThemedRoot {
                    AppGroupErrorView()
                }
            }
        }
    }
}
