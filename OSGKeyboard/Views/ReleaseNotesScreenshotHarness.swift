// ReleaseNotesScreenshotHarness.swift
// OSGKeyboard · Main App
//
// Deterministic DEBUG hosts for capturing real production cards used by the
// remote What's New page. These hosts seed only simulator-local fixture data.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

@MainActor
struct PolishStylesScreenshotHarness: View {
    private let language: AppUILanguage

    init() {
        language = ReleaseNotesScreenshotFixture.language
        ProviderConfig.shared.uiLanguage = language
        ReleaseNotesScreenshotFixture.seedReadyStyleCorpus(language: language)
    }

    var body: some View {
        ThemedRoot {
            PolishStylesView()
        }
        .environment(\.locale, language.swiftUILocale)
        .preferredColorScheme(.light)
    }
}

@MainActor
struct HomeDictionaryScreenshotHarness: View {
    @StateObject private var flowManager = FlowSessionManager()
    private let language: AppUILanguage

    init() {
        language = ReleaseNotesScreenshotFixture.language
        ProviderConfig.shared.uiLanguage = language
        ReleaseNotesScreenshotFixture.seedFrequentTerms(language: language)
    }

    var body: some View {
        ThemedRoot {
            HomeView()
                .environmentObject(flowManager)
        }
        .environment(\.locale, language.swiftUILocale)
        .preferredColorScheme(.light)
    }
}

@MainActor
private enum ReleaseNotesScreenshotFixture {
    static var language: AppUILanguage {
        ProcessInfo.processInfo.arguments.contains("--screenshot-lang=en")
            ? .english
            : .chinese
    }

    static func seedReadyStyleCorpus(language: AppUILanguage) {
        let history = SpeechHistoryStore.shared
        history.clearAll()
        let token = language == .chinese ? "自然表达习惯" : "NaturalVoice"
        let sample = String(String(repeating: token, count: 500).prefix(2_500))
        history.append(
            text: sample,
            prePolishText: sample,
            engineMode: "local",
            source: .dictation
        )
        history.reloadFromDisk()
    }

    static func seedFrequentTerms(language: AppUILanguage) {
        let store = FrequentTermStore()
        store.clear()
        let terms = language == .chinese
            ? ["少数派", "工作流", "语音键盘"]
            : ["VoiceFlow", "PromptKit", "OSGAgent"]
        for term in terms {
            for _ in 0..<4 {
                store.recordCommittedText(term)
            }
        }
    }
}
#endif
