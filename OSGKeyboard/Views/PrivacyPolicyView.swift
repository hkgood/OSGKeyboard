// PrivacyPolicyView.swift
// OSGKeyboard · Main App
//
// Bundled privacy policy HTML. Reached from Settings → About.

import SwiftUI
import OSGKeyboardShared

struct PrivacyPolicyView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject private var config = ProviderConfig.shared

    var body: some View {
        LegalWebView(
            resourceName: "PrivacyPolicy",
            scrollToAnchor: privacyScrollAnchor
        )
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.privacy.policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var privacyScrollAnchor: String? {
        switch config.uiLanguage {
        case .chinese:
            return "zh"
        case .english:
            return "top"
        case .auto:
            return config.uiLanguage.resolvedLanguageCode().hasPrefix("zh") ? "zh" : "top"
        }
    }
}
