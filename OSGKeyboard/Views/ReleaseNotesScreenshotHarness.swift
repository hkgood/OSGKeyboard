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
    private let usesServiceBackedGeneration: Bool
    private let usesInsufficientEvidence: Bool
    private let failsServiceBackedSynthesis: Bool
    private let delaysServiceBackedGeneration: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        language = ReleaseNotesScreenshotFixture.language
        ProviderConfig.shared.uiLanguage = language
        ReleaseNotesScreenshotFixture.seedReadyStyleCorpus(language: language)
        let testsWithoutCorpus = arguments.contains(
            "--polish-styles-service-ui-test-no-corpus"
        )
        if testsWithoutCorpus {
            SpeechHistoryStore.shared.clearAll()
        }
        simulatesGeneration = arguments.contains(
            "--polish-styles-generation-demo"
        )
        usesInsufficientEvidence = arguments.contains(
            "--polish-styles-service-ui-test-insufficient"
        )
        failsServiceBackedSynthesis = arguments.contains(
            "--polish-styles-service-ui-test-failure"
        )
        delaysServiceBackedGeneration = arguments.contains(
            "--polish-styles-service-ui-test-cancel"
        )
        let testsRegeneration = arguments.contains(
            "--polish-styles-service-ui-test-regenerate"
        )
        usesServiceBackedGeneration = usesInsufficientEvidence
            || failsServiceBackedSynthesis
            || delaysServiceBackedGeneration
            || testsRegeneration
            || arguments.contains(
                "--polish-styles-service-ui-test"
            )
        if simulatesGeneration || usesServiceBackedGeneration {
            ReleaseNotesScreenshotFixture.resetStyleCatalog()
        }
        if testsRegeneration || failsServiceBackedSynthesis {
            ReleaseNotesScreenshotFixture.seedGeneratedStyle(language: language)
        }
        showsSavedGeneratedStyle = arguments.contains(
            "--polish-styles-generated-saved"
        )
        generatedPack = arguments.contains(
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
            if usesServiceBackedGeneration {
                PolishStylesServiceUITestHarness(
                    usesInsufficientEvidence: usesInsufficientEvidence,
                    failsSynthesis: failsServiceBackedSynthesis,
                    delaysGeneration: delaysServiceBackedGeneration
                )
            } else if simulatesGeneration {
                PersonalReplyStyleHost(
                    generator: { _, _, language in
                        try await Task.sleep(for: .seconds(1.8))
                        return ReleaseNotesScreenshotFixture.generatedStyle(
                            language: language
                        )
                    }
                )
            } else if let generatedPack {
                PersonalReplyStyleHost(initialEditingPack: generatedPack)
            } else {
                PersonalReplyStyleHost()
            }
        }
        .environment(\.locale, language.swiftUILocale)
        .preferredColorScheme(.light)
    }
}

/// Exercises the production learning service without network access. Unlike
/// release-note fixtures, this host scripts only the LLM boundary and lets the
/// real two-stage extractor/synthesizer pipeline build the review pack.
@MainActor
private struct PolishStylesServiceUITestHarness: View {
    let usesInsufficientEvidence: Bool
    let failsSynthesis: Bool
    let delaysGeneration: Bool

    @StateObject private var recorder = PolishStylesUITestRecorder()
    @State private var showsStyles = true

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if showsStyles {
                PersonalReplyStyleHost(
                    generator: { corpus, replyExamples, language in
                        let client = PolishStylesUITestScriptedLLMClient(
                            responses: ReleaseNotesScreenshotFixture.serviceResponses(
                                language: language,
                                usesInsufficientEvidence: usesInsufficientEvidence,
                                failsSynthesis: failsSynthesis
                            ),
                            delay: delaysGeneration ? 5 : 0.15,
                            recorder: recorder
                        )
                        return try await PolishStyleLearningService(
                            store: AppGroupStore(),
                            client: client
                        )
                        .generateStyle(
                            from: corpus,
                            replyExamples: replyExamples,
                            outputLanguage: language,
                            minimumEffectiveCharacterCount:
                                AppDistributionChannel.allowsInternalTools
                                    ? PolishStyleLearningCorpusBuilder
                                        .testBuildEffectiveCharacterCount
                                    : PolishStyleLearningCorpusBuilder
                                        .requiredEffectiveCharacterCount
                        )
                    }
                )
            } else {
                VStack(spacing: 16) {
                    Text("Style view closed")
                        .accessibilityIdentifier("polishStyles.test.closed")
                    if recorder.didObserveCancellation {
                        Text("Generation cancellation observed")
                            .accessibilityIdentifier("polishStyles.test.cancelled")
                    }
                    Button("Return to styles") {
                        showsStyles = true
                    }
                    .accessibilityIdentifier("polishStyles.test.return")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if delaysGeneration, showsStyles {
                Button("Leave styles") {
                    showsStyles = false
                }
                .accessibilityIdentifier("polishStyles.test.leave")
                .padding()
            }
        }
    }
}

/// Personal-style generation moved to the Skills tab when voice input and AI
/// replies were split, so these hosts drive the section directly instead of the
/// Styles page.
@MainActor
private struct PersonalReplyStyleHost: View {
    let initialEditingPack: PolishStylePack?
    let generator: LearnedStyleGenerator?

    init(
        initialEditingPack: PolishStylePack? = nil,
        generator: LearnedStyleGenerator? = nil
    ) {
        self.initialEditingPack = initialEditingPack
        self.generator = generator
    }

    var body: some View {
        ScrollView {
            CardPageContent {
                if let generator {
                    PersonalReplyStyleSection(
                        initialEditingPack: initialEditingPack,
                        generator: generator
                    )
                } else {
                    PersonalReplyStyleSection(initialEditingPack: initialEditingPack)
                }
            }
        }
    }
}

@MainActor
private final class PolishStylesUITestRecorder: ObservableObject {
    @Published var didObserveCancellation = false

    func markCancellationObserved() {
        didObserveCancellation = true
    }
}

private final class PolishStylesUITestScriptedLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15

    private let responses: [String]
    private let delay: TimeInterval
    private let recorder: PolishStylesUITestRecorder
    private var responseIndex = 0

    init(
        responses: [String],
        delay: TimeInterval,
        recorder: PolishStylesUITestRecorder
    ) {
        self.responses = responses
        self.delay = delay
        self.recorder = recorder
    }

    func polish(
        _: String,
        systemPrompt: String,
        timeout _: TimeInterval?
    ) async throws -> String {
        try await response(for: systemPrompt)
    }

    func polish(
        _: String,
        systemPrompt: String,
        timeout _: TimeInterval?,
        options _: LLMGenerationOptions
    ) async throws -> String {
        try await response(for: systemPrompt)
    }

    private func response(for _: String) async throws -> String {
        do {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(delay))
            try Task.checkCancellation()
        } catch is CancellationError {
            await recorder.markCancellationObserved()
            throw CancellationError()
        }
        guard !responses.isEmpty else { return "{}" }
        let index = min(responseIndex, responses.count - 1)
        responseIndex += 1
        return responses[index]
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
        ReleaseNotesScreenshotFixture.seedMonthlyUsage()
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

    static func serviceResponses(
        language: AppUILanguage,
        usesInsufficientEvidence: Bool,
        failsSynthesis: Bool
    ) -> [String] {
        if failsSynthesis {
            return [
                sufficientEvidenceResponse,
                "invalid synthesis response",
                "invalid synthesis repair response"
            ]
        }
        if usesInsufficientEvidence {
            return [
                insufficientEvidenceResponse,
                generatedStyleResponse(language: language)
            ]
        }
        return [
            sufficientEvidenceResponse,
            generatedStyleResponse(language: language)
        ]
    }

    private static let sufficientEvidenceResponse = ##"""
    {
      "status":"sufficient",
      "confidence":0.86,
      "asr":{
        "traits":[
          {"name":"concise and direct","description":"The user repeatedly preserves concise direct wording","confidence":0.9,"supportCount":4}
        ],
        "evidence":[
          {"source":"asrUserEdit","summary":"User edits preserve direct wording","supportCount":2},
          {"source":"asrRepeatedBefore","summary":"Short direct phrases recur in dictation","supportCount":4}
        ],
        "contradictions":[]
      },
      "reply":{
        "traits":[
          {"name":"relaxed replies","description":"The user prefers relaxed replies without invented information","confidence":0.7,"supportCount":2}
        ],
        "evidence":[
          {"source":"replyFinalEdit","summary":"Final edits preserve natural short sentences","supportCount":1},
          {"source":"replyCrossContextSelection","summary":"Relaxed tone is preferred across contexts","supportCount":2},
          {"source":"replyAcceptance","summary":"A single acceptance remains weak evidence","supportCount":1}
        ],
        "contradictions":[]
      }
    }
    """##

    private static let insufficientEvidenceResponse = ##"""
    {
      "status":"insufficient",
      "confidence":0.2,
      "asr":{
        "traits":[
          {"name":"retention:direct short phrasing","description":"The raw ASR uses a direct short-message rhythm","confidence":0.2,"supportCount":1}
        ],
        "evidence":[
          {"source":"asrObservedBefore","summary":"A raw before sample uses direct short phrasing","supportCount":1}
        ],
        "contradictions":[]
      },
      "reply":{"traits":[],"evidence":[],"contradictions":[]}
    }
    """##

    private static func generatedStyleResponse(language: AppUILanguage) -> String {
        if language == .chinese {
            return ##"""
            {
              "name":"我的说话风格",
              "prompt":"# 角色\n保留用户自然、直接的表达方式。\n# 风格边界\nASR preserve mode：只修正识别错误与标点，不改变原意。\nAI reply active-transfer mode：先回应，再补充必要信息，不虚构事实或承诺。\n# 示例\n原文：这个我晚点确认一下\n输出：这个我晚点确认一下。",
              "allowsAddedEmoji":false
            }
            """##
        }
        return ##"""
        {
          "name":"My Speaking Style",
          "prompt":"# 角色\nPreserve the user's natural, direct voice.\n# 风格边界\nASR preserve mode: correct recognition and punctuation without changing intent.\nAI reply active-transfer mode: respond first, add only necessary detail, and invent no facts or commitments.\n# 示例\nDraft: I will check later\nOutput: I'll check later.",
          "allowsAddedEmoji":false
        }
        """##
    }

    static func seedGeneratedStyle(language: AppUILanguage) {
        let pack = generatedStyle(language: language)
        var catalog = PolishStyleCatalog()
        try? catalog.upsert(pack)
        let store = AppGroupStore()
        store.setPolishStyleCatalog(catalog)
        // A distilled pack drives AI replies, not dictation; the voice-style
        // setter would reject it.
        store.setPersonalReplyStyleId(pack.id)
    }

    static func resetStyleCatalog() {
        let store = AppGroupStore()
        store.setPolishStyleCatalog(PolishStyleCatalog())
        store.setActivePolishStyleId(PolishStylePackCatalog.defaultID)
        store.setPersonalReplyStyleId("")
    }

    /// Seeds varied per-day dictation totals across the current month so the
    /// Home monthly-usage calendar renders a realistic spread instead of an
    /// empty grid. Writes this device's slice only, mirroring `recordUtterance`.
    static func seedMonthlyUsage() {
        let store = UsageStatisticsStore.shared
        let defaults = store.defaults
        var slice = SyncedUsageStatisticsStorage.currentDeviceSlice(from: defaults)
        let calendar = Calendar.current
        let today = Date()
        let dayOfMonth = calendar.component(.day, from: today)
        let pattern = [
            420, 980, 0, 260, 1360, 640, 180, 0, 1120, 540,
            760, 300, 1500, 220, 880, 0, 640, 1180, 360, 940
        ]
        var daily: [String: Int] = [:]
        var total = 0
        for offset in 0..<dayOfMonth {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today)
            else { continue }
            let value = pattern[offset % pattern.count]
            guard value > 0 else { continue }
            daily[UsageStatisticsDayKey.key(for: date)] = value
            total += value
        }
        slice.dailyDictationCharacters = daily
        slice.dictationCharacterCount = total
        slice.updatedAt = today
        SyncedUsageStatisticsStorage.upsertCurrentDeviceSlice(slice, defaults: defaults)
        store.reloadFromDisk()
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
