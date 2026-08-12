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
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--whats-new-host") {
                // Approach A: Notes-like host only; real keyboard extension overlays it.
                Self.makeWhatsNewHostView()
            } else if ProcessInfo.processInfo.arguments.contains("--edit-demo") {
                EditDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("--ai-demo") {
                AIKeyboardDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("--clipboard-demo") {
                ClipboardHistoryDemoView()
            } else if ProcessInfo.processInfo.arguments.contains("--edit-pager-ui-test") {
                ThemedRoot {
                    EditPagerUITestHarness()
                }
                .preferredColorScheme(appearance.colorScheme)
            } else if AppGroup.isAvailable {
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
            #else
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
            #endif
        }
    }

    #if DEBUG
    @MainActor
    private static func makeWhatsNewHostView() -> some View {
        let args = ProcessInfo.processInfo.arguments
        let scenario = whatsNewScenario(from: args) ?? .edit
        let language = whatsNewLanguage(from: args)
        let seed = whatsNewSeedText(for: scenario, language: language)
        WhatsNewDemoScenario.clear()
        WhatsNewDemoScenario.arm(scenario, seedText: seed, language: language)
        if let defaults = AppGroup.defaultsIfAvailable {
            defaults.set(true, forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding)
            // Force extension ExtL10n / SharedL10n into the demo language.
            defaults.set(
                (language == .en ? AppUILanguage.english : AppUILanguage.chinese).rawValue,
                forKey: AppGroupConfiguration.Keys.uiLanguage
            )
            // Clipboard demo needs history + suggestion strip flags on.
            if scenario == .clipboard {
                defaults.set(true, forKey: AppGroupConfiguration.Keys.clipboardHistoryEnabled)
                defaults.set(
                    true,
                    forKey: AppGroupConfiguration.Keys.clipboardCandidateBarEnabled
                )
            }
            defaults.synchronize()
        }
        return NotesHostDemoView(
            scenario: scenario,
            seedText: seed,
            language: language
        )
    }

    private static func whatsNewScenario(from args: [String]) -> WhatsNewDemoScenario? {
        if let paired = args.first(where: { $0.hasPrefix("--whats-new-scenario=") }) {
            let raw = String(paired.dropFirst("--whats-new-scenario=".count))
            return WhatsNewDemoScenario(rawValue: raw)
        }
        if let idx = args.firstIndex(of: "--whats-new-scenario"),
           args.index(after: idx) < args.endIndex
        {
            return WhatsNewDemoScenario(rawValue: args[args.index(after: idx)])
        }
        return nil
    }

    private static func whatsNewLanguage(from args: [String]) -> WhatsNewDemoScenario.Language {
        if let paired = args.first(where: { $0.hasPrefix("--whats-new-lang=") }) {
            let raw = String(paired.dropFirst("--whats-new-lang=".count))
            return WhatsNewDemoScenario.Language(rawValue: raw) ?? .zh
        }
        if let idx = args.firstIndex(of: "--whats-new-lang"),
           args.index(after: idx) < args.endIndex
        {
            return WhatsNewDemoScenario.Language(
                rawValue: args[args.index(after: idx)]
            ) ?? .zh
        }
        return .zh
    }

    private static func whatsNewSeedText(
        for scenario: WhatsNewDemoScenario,
        language: WhatsNewDemoScenario.Language
    ) -> String {
        switch (scenario, language) {
        case (.edit, .zh):
            return "明天下午三点开会讨论方案"
        case (.edit, .en):
            return "Meeting at 3pm tomorrow to discuss the plan"
        case (.ai, .zh):
            return "周末想找个地方放松一下"
        case (.ai, .en):
            return "Looking for a place to relax this weekend"
        case (.clipboard, .zh):
            return "待办："
        case (.clipboard, .en):
            return "Todo: "
        }
    }
    #endif
}
