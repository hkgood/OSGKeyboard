// ReleaseNotesSheet.swift
// OSGKeyboard · Main App
//
// Sheet that loads the remote release-notes HTML for the current version.

import OSGKeyboardShared
import SwiftUI

struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.colorScheme) private var colorScheme

    /// In-app UI language (not system-only) — chrome strings go through `AppL10n`.
    let language: AppUILanguage

    @AppStorage(AppearancePreference.storageKey)
    private var appearanceRaw = AppearancePreference.system.rawValue

    @State private var isLoading = true

    private var appearance: AppearancePreference {
        AppearancePreference.fromStored(appearanceRaw)
    }

    /// Theme actually shown in this sheet (honors Settings → Appearance).
    private var resolvedColorScheme: ColorScheme {
        appearance.colorScheme ?? colorScheme
    }

    var body: some View {
        NavigationStack {
            Group {
                if let url = ReleaseNotesStore.pageURL(
                    language: language,
                    colorScheme: resolvedColorScheme
                ) {
                    ZStack {
                        // Fill the sheet body edge-to-edge (including home-indicator
                        // band). WKWebView otherwise sits above a blank safe-area strip.
                        RemoteWebView(
                            url: url,
                            isLoading: $isLoading,
                            neutralizeSafeAreaPadding: true
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea(edges: .bottom)

                        if isLoading {
                            ProgressView()
                                .tint(palette.accent)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        AppL10n.string("releaseNotes.unavailable.title", language: language),
                        systemImage: "wifi.slash",
                        description: Text(
                            AppL10n.string("releaseNotes.unavailable.message", language: language)
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background.ignoresSafeArea())
            .navigationTitle(AppL10n.string("releaseNotes.title", language: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppL10n.string("common.done", language: language)) {
                        dismiss()
                    }
                }
            }
        }
        // Force full-height sheet so the web view isn't clipped under a mid detent.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Sheet can drop WindowGroup environment; re-assert language + appearance.
        .environment(\.locale, language.swiftUILocale)
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.themePalette, resolvedColorScheme == .dark ? Palette.dark : Palette.light)
    }
}
