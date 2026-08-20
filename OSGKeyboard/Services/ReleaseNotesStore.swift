// ReleaseNotesStore.swift
// OSGKeyboard · Main App
//
// Tracks which marketing version's release notes the user has already seen,
// and builds the remote release-notes URL with v / lang / theme query params.

import Foundation
import OSGKeyboardShared
import SwiftUI

enum ReleaseNotesStore {
    static let lastSeenKey = "config.lastSeenMarketingVersion"
    static let pageURLString = "https://download.osglab.com/osgkeyboardversion.html"

    static var lastSeenMarketingVersion: String? {
        get {
            UserDefaults.standard.string(forKey: lastSeenKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: lastSeenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastSeenKey)
            }
        }
    }

    /// True when the user has not acknowledged the current marketing version.
    static var shouldPresentAutomatically: Bool {
        let current = AppVersionDisplay.marketingVersion
        guard current != "—" else { return false }
        return lastSeenMarketingVersion != current
    }

    static func markCurrentVersionSeen() {
        let current = AppVersionDisplay.marketingVersion
        guard current != "—" else { return }
        lastSeenMarketingVersion = current
    }

    /// Query language for the remote page (`zh` / `en`).
    static func queryLanguage(for uiLanguage: AppUILanguage) -> String {
        let code = uiLanguage.resolvedLanguageCode()
        return code.hasPrefix("zh") ? "zh" : "en"
    }

    /// Query theme for the remote page (`light` / `dark`).
    static func queryTheme(for colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "dark" : "light"
    }

    static func pageURL(
        version: String = AppVersionDisplay.marketingVersion,
        language: AppUILanguage,
        colorScheme: ColorScheme
    ) -> URL? {
        guard version != "—",
              var components = URLComponents(string: pageURLString) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "v", value: version),
            URLQueryItem(name: "lang", value: queryLanguage(for: language)),
            URLQueryItem(name: "theme", value: queryTheme(for: colorScheme))
        ]
        return components.url
    }
}

@MainActor
final class ReleaseNotesController: ObservableObject {
    static let shared = ReleaseNotesController()

    @Published var isPresented = false

    func presentIfNeeded(onboardingCompleted: Bool) {
        guard onboardingCompleted, ReleaseNotesStore.shouldPresentAutomatically else { return }
        isPresented = true
    }

    func presentManually() {
        isPresented = true
    }
}
