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
    private let generatedPack: PolishStylePack?
    private let showsSavedGeneratedStyle: Bool
    private let simulatesGeneration: Bool

    init() {
        language = ReleaseNotesScreenshotFixture.language
        ProviderConfig.shared.uiLanguage = language
        ReleaseNotesScreenshotFixture.seedReadyStyleCorpus(language: language)
        simulatesGeneration = ProcessInfo.processInfo.arguments.contains(
            "--polish-styles-generation-demo"
        )
        if simulatesGeneration {
            ReleaseNotesScreenshotFixture.resetStyleCatalog()
        }
        showsSavedGeneratedStyle = ProcessInfo.processInfo.arguments.contains(
            "--polish-styles-generated-saved"
        )
        generatedPack = ProcessInfo.processInfo.arguments.contains(
            "--polish-styles-generated-review"
        )
            ? ReleaseNotesScreenshotFixture.generatedStyle(language: language)
            : nil
        if showsSavedGeneratedStyle {
            ReleaseNotesScreenshotFixture.seedGeneratedStyle(language: language)
        }
    }

    var body: some View {
        ThemedRoot {
            if simulatesGeneration {
                PolishStylesView(
                    learnedStyleGenerator: { _, _, language in
                        try await Task.sleep(for: .seconds(1.8))
                        return ReleaseNotesScreenshotFixture.generatedStyle(
                            language: language
                        )
                    }
                )
            } else {
                PolishStylesView(initialEditingPack: generatedPack)
            }
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

    static func generatedStyle(language: AppUILanguage) -> PolishStylePack {
        let isChinese = language == .chinese
        return PolishStylePack(
            name: isChinese ? "我的说话风格" : "My Speaking Style",
            prompt: isChinese
                ? """
                # 角色
                保留用户自然、直接的表达方式，优先使用简短口语，不写成客服或公文语气。

                # 风格边界
                ASR preserve mode：只整理识别错误、标点和明显重复，不改变原意、措辞习惯与直接程度。
                AI reply active-transfer mode：主动使用自然短句，先回应对方，再补充必要信息；不复述对方原文，不虚构立场、事实或承诺。
                熟人闲聊可以使用符合语境的轻松幽默和 emoji，严肃场景保持克制。

                # 示例
                原文：这个我晚点确认一下然后再跟你说
                输出：这个我晚点确认一下，再跟你说。

                收到：今天可能要晚一点到
                回复：好，没事，你路上慢点。
                """
                : """
                # Role
                Preserve the user's natural, direct voice with concise everyday wording.

                # Style Boundaries
                ASR preserve mode: correct recognition and punctuation without changing intent.
                AI reply active-transfer mode: respond first, add only necessary detail, never restate the sender's message, and invent no facts or commitments.
                Light contextual humor and emoji are welcome with friends; stay restrained in serious contexts.

                # Examples
                Draft: I will check this later and let you know
                Output: I'll check later and let you know.
                """,
            learningMetadata: PolishStylePack.LearningMetadata(
                schemaVersion: 2,
                evidenceStatus: "sufficient",
                confidence: 0.86,
                asrExampleCount: 42,
                asrEffectiveCharacterCount: 2_735,
                replyExampleCount: 12,
                replyFinalEditCount: 4,
                generatedAt: Date()
            )
        )
    }

    static func seedGeneratedStyle(language: AppUILanguage) {
        let pack = generatedStyle(language: language)
        var catalog = PolishStyleCatalog()
        try? catalog.upsert(pack)
        let store = AppGroupStore()
        store.setPolishStyleCatalog(catalog)
        store.setActivePolishStyleId(pack.id)
    }

    static func resetStyleCatalog() {
        let store = AppGroupStore()
        store.setPolishStyleCatalog(PolishStyleCatalog())
        store.setActivePolishStyleId(PolishStylePackCatalog.defaultID)
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
