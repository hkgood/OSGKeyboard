// HelpFeedbackView.swift
// OSGKeyboard · Main App
//
// In-app GitHub Issues page. Reached from Settings → About.

import SwiftUI
import OSGKeyboardShared

struct HelpFeedbackView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @State private var isLoading = true

    var body: some View {
        Group {
            if let url = LegalLinks.supportURL {
                ZStack {
                    RemoteWebView(url: url, isLoading: $isLoading)
                    if isLoading {
                        ProgressView()
                            .tint(palette.accent)
                    }
                }
            } else {
                ContentUnavailableView(
                    "settings.support.unavailable.title",
                    systemImage: "wifi.slash",
                    description: Text("settings.support.unavailable.message")
                )
            }
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.link.support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
