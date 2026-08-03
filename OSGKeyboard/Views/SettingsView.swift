// SettingsView.swift
// OSGKeyboard · Main App
//
// Settings home: daily controls + summary navigation into secondary
// pages for low-frequency configuration.

import SwiftUI
import OSGKeyboardShared

enum SettingsPresentation {
    case tab
    case sheet
}

/// Routes pushed from Settings home. Value-based navigation keeps
/// destinations out of the root view tree until push — important so
/// `hidesTabBarWhenPushed()` preferences do not leak onto the home
/// screen (and so we avoid NavigationLink + `dismiss` freeze cycles).
private enum SettingsRoute: Hashable {
    case speechRecognition
    case textPolish
    case general
    case about
}

struct SettingsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config = ProviderConfig.shared

    let presentation: SettingsPresentation

    init(presentation: SettingsPresentation = .sheet) {
        self.presentation = presentation
    }

    // Dynamic locale list loaded from SFSpeechRecognizer on first appear.
    @State private var dynamicLocales: [(id: String, onDevice: Bool)] = []
    @State private var showResetConfirmation = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                palette.background.ignoresSafeArea()
                ScrollView {
                    CardPageContent {
                        if presentation == .tab {
                            SupportDeveloperSection(language: config.uiLanguage)
                        }
                        dailySection
                        transcriptionAndPolishSection
                        if presentation == .tab {
                            moreEntriesSection
                        }
                    }
                    .modifier(SettingsScrollBottomPadding(presentation: presentation))
                }
            }
            .background(palette.background)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showResetConfirmation = true
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("settings.reset.confirm")
                    .confirmationDialog(
                        "settings.reset.title",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("common.reset", role: .destructive) {
                            config.reset()
                            SpeechHistoryStore.shared.clearAll()
                        }
                        Button("common.cancel", role: .cancel) {}
                    } message: {
                        Text("settings.reset.message")
                    }
                }
                if presentation == .sheet {
                    ToolbarItem(placement: .confirmationAction) {
                        // Keep `dismiss` off the Settings root — pairing it
                        // with NavigationLink / stack pushes can freeze UI.
                        SettingsSheetDismissButton()
                    }
                }
            }
            .navigationDestination(for: SettingsRoute.self) { route in
                settingsDestination(for: route)
            }
            .task { await loadDynamicLocales() }
        }
    }

    @ViewBuilder
    private func settingsDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .speechRecognition:
            SpeechRecognitionSettingsView(config: config)
        case .textPolish:
            TextPolishSettingsView(config: config)
        case .general:
            GeneralSettingsView(config: config)
        case .about:
            AboutSettingsView(config: config)
        }
    }

    // MARK: - Daily (high-frequency)

    private var dailySection: some View {
        CardSection("settings.daily.title") {
            VStack(spacing: 0) {
                settingsRouteButton(.general, title: "settings.general.title")

                Divider().background(palette.divider)

                LocalePickerRow(
                    locales: effectiveLocales,
                    selection: Binding(
                        get: { config.localeId },
                        set: { config.localeId = $0 }
                    )
                )

                Divider().background(palette.divider)

                PolishIntensityPickerRow(config: config)

                Divider().background(palette.divider)

                TranslationPickerRow(config: config, isVisible: config.isTranslationRowVisible)

                Divider().background(palette.divider)

                VoiceSessionSettingsRows(config: config)
            }
            .surfaceCard()
        }
    }

    // MARK: - Transcription & polish

    private var transcriptionAndPolishSection: some View {
        EnginePickerSection(config: config) {
            Divider().background(palette.divider)

            settingsRouteButton(
                .speechRecognition,
                title: "settings.speechRecognition.title",
                subtitle: SettingsConfigSummary.speechRecognition(config: config)
            )

            Divider().background(palette.divider)

            settingsRouteButton(
                .textPolish,
                title: "settings.textPolish.title",
                subtitle: SettingsConfigSummary.textPolish(config: config)
            )
        }
    }

    // MARK: - About

    private var moreEntriesSection: some View {
        VStack(spacing: 0) {
            settingsRouteButton(.about, title: "settings.about.title")
        }
        .surfaceCard()
    }

    private func settingsRouteButton(
        _ route: SettingsRoute,
        title: LocalizedStringKey,
        subtitle: String? = nil
    ) -> some View {
        Button {
            path.append(route)
        } label: {
            SettingsNavigationRow(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Locale helpers

    /// Falls back to a static list while dynamic locales are loading.
    private var effectiveLocales: [(id: String, onDevice: Bool)] {
        dynamicLocales.isEmpty ? SettingsASRLocales.staticFallback : dynamicLocales
    }

    private func loadDynamicLocales() async {
        dynamicLocales = await SettingsASRLocales.loadDynamic()
    }
}

// MARK: - Sheet dismiss (isolated from Settings root)

private struct SettingsSheetDismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("common.done") { dismiss() }
    }
}

// MARK: - Tab dock bottom padding (tab root only)

private struct SettingsScrollBottomPadding: ViewModifier {
    let presentation: SettingsPresentation

    func body(content: Content) -> some View {
        if presentation == .tab {
            content.tabBarScrollBottomPadding()
        } else {
            content.padding(.bottom, Spacing.lg)
        }
    }
}
