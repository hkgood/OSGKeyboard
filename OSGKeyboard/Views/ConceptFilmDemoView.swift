// ConceptFilmDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// Recording host for the vertical concept film. Each launch plays one scripted
// beat on the **real** views — `AIKeyboardView` and `PersonalReplyStyleSection`
// — with no ASR, no LLM, and no network:
//
//   --concept-film=voice   rambling dictation → polished text lands in Notes
//   --concept-film=style   personal reply style distilled from past dictation
//   --concept-film=reply   copied message → three reply choices → sent
//
// Optional `--whats-new-lang=zh|en`. Timelines run at wall-clock speed; the
// film edit trims and retimes them.
//
// Simulator-only: the style scene clears speech history and replaces the style
// catalog. Those writes carry iCloud-synced tombstones, so on a personal device
// they would wipe the same data on every device signed into that account.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct ConceptFilmDemoView: View {
    enum Scene: String {
        case voice
        case style
        case reply
    }

    let scene: Scene

    static var requestedScene: Scene? {
        #if !targetEnvironment(simulator)
        return nil
        #else
        let prefix = "--concept-film="
        guard let argument = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix(prefix) }
        ) else {
            return nil
        }
        return Scene(rawValue: String(argument.dropFirst(prefix.count)))
        #endif
    }

    private var language: WhatsNewDemoScenario.Language {
        let prefix = "--whats-new-lang="
        guard let argument = ProcessInfo.processInfo.arguments.first(
            where: { $0.hasPrefix(prefix) }
        ) else {
            return .zh
        }
        return WhatsNewDemoScenario.Language(
            rawValue: String(argument.dropFirst(prefix.count))
        ) ?? .zh
    }

    var body: some View {
        Group {
            switch scene {
            case .voice:
                ConceptVoiceScene(language: language)
            case .style:
                ConceptStyleScene(language: language)
            case .reply:
                ConceptReplyScene(language: language)
            }
        }
        .environment(\.locale, language.locale)
        .preferredColorScheme(.light)
    }
}

// MARK: - Voice: 你说 / You speak

private struct ConceptVoiceScene: View {
    let language: WhatsNewDemoScenario.Language

    @ObservedObject private var config = ProviderConfig.shared
    @State private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @State private var hostText = ""

    init(language: WhatsNewDemoScenario.Language) {
        self.language = language
        AIKeyboardView.debugSkipsLongPressCoach = true
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                FeaturePreviewHostDocument(
                    kind: .notes,
                    title: language == .en ? "Notes" : "备忘录",
                    language: language,
                    text: hostText
                )
                AIKeyboardView(state: state, typing: typing, onInsert: { _ in })
                    .background(Palette.light.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .conceptKeyboardWidth(state)
        .task { await runTimeline() }
    }

    /// Idle → recording with the raw transcript streaming in (fillers and a
    /// self-correction included) → processing → the polished sentence lands
    /// in the note while the mic flashes the success state.
    private func runTimeline() async {
        config.uiLanguage = language.uiLanguage
        state.prepareConceptKeyboard()
        await pause(1.2)

        withAnimation(.easeOut(duration: 0.2)) {
            state.phase = .recording
        }
        for chunk in ConceptFilmScript.spokenChunks(language) {
            state.lastTranscript += chunk
            // Several level ticks per chunk keep the waveform alive between words.
            for _ in 0..<3 {
                state.level = Double.random(in: 0.3...0.9)
                await pause(0.1)
            }
        }

        withAnimation(.easeOut(duration: 0.2)) {
            state.phase = .processing
            state.level = 0
        }
        await pause(1.0)

        withAnimation(.easeOut(duration: 0.25)) {
            state.phase = .idle
            state.lastTranscript = ""
            state.assistantInsertionSucceeded = true
            hostText = ConceptFilmScript.polishedText(language)
        }
        await pause(1.6)
        withAnimation(.easeOut(duration: 0.25)) {
            state.assistantInsertionSucceeded = false
        }
        await pause(60)
    }
}

// MARK: - Style: 它学 / It learns

private struct ConceptStyleScene: View {
    let language: WhatsNewDemoScenario.Language

    init(language: WhatsNewDemoScenario.Language) {
        self.language = language
        ConceptStyleFixture.prepareOnce(language: language)
    }

    var body: some View {
        ThemedRoot {
            NavigationStack {
                ScrollView {
                    CardPageContent {
                        PersonalReplyStyleSection(generator: { _, _, _, _ in
                            try await Task.sleep(for: .seconds(2.4))
                            ConceptStyleFixture.saveLearnedStyle(language: language)
                            // Same reload path a cloud merge takes, so the card
                            // flips to the saved style without the review sheet.
                            withAnimation(.snappy(duration: 0.45)) {
                                NotificationCenter.default.post(
                                    name: .polishStylesDidSyncFromCloud,
                                    object: nil
                                )
                            }
                            throw CancellationError()
                        })
                    }
                }
                .background(Palette.light.background)
                .navigationTitle(AppL10n.string("skills.title"))
                .navigationBarTitleDisplayMode(.large)
            }
        }
    }
}

@MainActor
private enum ConceptStyleFixture {
    private static var didPrepare = false

    /// SwiftUI may re-create the scene struct; seeding again would reset the
    /// card mid-take.
    static func prepareOnce(language: WhatsNewDemoScenario.Language) {
        guard !didPrepare else { return }
        didPrepare = true

        ProviderConfig.shared.uiLanguage = language.uiLanguage
        PersonalReplyStyleSection.debugUsesReleaseCharacterGate = true
        PersonalReplyStyleSection.debugAutoGenerationDelay = .seconds(1.6)

        let store = AppGroupStore()
        store.setPolishStyleCatalog(PolishStyleCatalog())
        store.setActivePolishStyleId(PolishStylePackCatalog.defaultID)
        store.setPersonalReplyStyleId("")

        // Exactly the release gate, so the card reads "2500 / 2500" and ready.
        let history = SpeechHistoryStore.shared
        history.clearAll()
        let token = language == .en ? "NaturalVoice" : "自然表达习惯"
        let sample = String(
            String(repeating: token, count: 500)
                .prefix(PolishStyleLearningCorpusBuilder.requiredEffectiveCharacterCount)
        )
        history.append(
            text: sample,
            prePolishText: sample,
            engineMode: "local",
            source: .dictation
        )
        history.reloadFromDisk()
    }

    static func saveLearnedStyle(language: WhatsNewDemoScenario.Language) {
        let isEnglish = language == .en
        let pack = PolishStylePack(
            name: isEnglish ? "My Speaking Style" : "我的说话风格",
            prompt: isEnglish
                ? "Preserve the user's natural, direct voice. Respond first, add only necessary detail."
                : "保留用户自然、直接的表达方式。先回应对方，再补充必要信息。",
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
        var catalog = PolishStyleCatalog()
        try? catalog.upsert(pack)
        let store = AppGroupStore()
        store.setPolishStyleCatalog(catalog)
        store.setPersonalReplyStyleId(pack.id)
    }
}

// MARK: - Reply: 它替你说 / It speaks for you

private struct ConceptReplyScene: View {
    let language: WhatsNewDemoScenario.Language

    @ObservedObject private var config = ProviderConfig.shared
    @State private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @State private var hostText = ""
    @State private var hostSent = false

    init(language: WhatsNewDemoScenario.Language) {
        self.language = language
        AIKeyboardView.debugSkipsLongPressCoach = true
    }

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 0) {
                FeaturePreviewHostDocument(
                    kind: .messages,
                    title: language == .en ? "Messages" : "信息",
                    language: language,
                    text: hostText,
                    incoming: ConceptFilmScript.incomingMessage(language),
                    isSent: hostSent
                )
                AIKeyboardView(state: state, typing: typing, onInsert: { _ in })
                    .background(Palette.light.background.ignoresSafeArea(edges: .bottom))
            }
        }
        .conceptKeyboardWidth(state)
        .task { await runTimeline() }
    }

    /// Copied message → thinking → three reply choices → the first (the
    /// user's everyday voice) is chosen, inserted, and sent.
    private func runTimeline() async {
        config.uiLanguage = language.uiLanguage
        state.prepareConceptKeyboard()
        state.clipboardHistoryEnabled = true
        state.clipboardSuggestionText = ConceptFilmScript.incomingMessage(language)
        await pause(1.4)

        let utteranceID = UUID()
        state.aiSession.beginPreparing(utteranceID: utteranceID)
        state.aiSession.beginGenerating(question: "", utteranceID: utteranceID)
        await pause(1.2)

        let variants = ConceptFilmScript.replyVariants(language)
        withAnimation(.snappy(duration: 0.4)) {
            state.aiSession.receiveReplyVariants(variants, utteranceID: utteranceID)
        }
        await pause(2.8)

        guard let chosen = variants.first else { return }
        withAnimation(.snappy(duration: 0.3)) {
            _ = state.aiSession.selectReplyVariant(id: chosen.id)
        }
        await pause(0.9)

        withAnimation(.easeOut(duration: 0.25)) {
            state.aiSession.markAnswerInserted(offersSend: true)
            hostText = chosen.text
        }
        await pause(1.0)
        withAnimation(.easeOut(duration: 0.25)) {
            state.aiSession.markAnswerSent()
            hostSent = true
        }
        await pause(60)
    }
}

// MARK: - Script

private enum ConceptFilmScript {
    /// Raw ASR as it streams: fillers plus an explicit self-correction, both
    /// of which the polish prompt removes (F1 / R4 in `PolishPromptComposer`).
    static func spokenChunks(_ language: WhatsNewDemoScenario.Language) -> [String] {
        language == .en
            ? ["Um, ", "so ", "let's meet ", "tomorrow at ", "two, ", "oh wait, ",
               "three, ", "to go over ", "the, uh, ", "proposal"]
            : ["嗯，", "那个，", "明天下午", "两点，", "哦不对，", "三点，",
               "开个会", "讨论一下", "那个方案"]
    }

    static func polishedText(_ language: WhatsNewDemoScenario.Language) -> String {
        language == .en
            ? "Let's meet tomorrow at three to go over the proposal."
            : "明天下午三点开会，讨论一下方案。"
    }

    static func incomingMessage(_ language: WhatsNewDemoScenario.Language) -> String {
        language == .en
            ? "Read the proposal. Can you send the budget version tomorrow?"
            : "方案我看了，明天能不能把预算那一版也发我？"
    }

    /// English lines are kept short so all three rows fit the keyboard band
    /// without scrolling, matching the 1 / 2 / 1 line rhythm of the Chinese take.
    static func replyVariants(_ language: WhatsNewDemoScenario.Language) -> [AIReplyVariant] {
        if language == .en {
            return [
                AIReplyVariant(
                    kind: .ordinary,
                    emotion: .neutral,
                    text: "Sure, I'll send it over tomorrow."
                ),
                AIReplyVariant(
                    kind: .formal,
                    emotion: .neutral,
                    text: "Received. I'll send the budget version to you tomorrow morning."
                ),
                AIReplyVariant(
                    kind: .playful,
                    emotion: .playful,
                    text: "You got it, budget's on its way!"
                )
            ]
        }
        return [
            AIReplyVariant(
                kind: .ordinary,
                emotion: .neutral,
                text: "没问题，预算那版我今晚整理好，明早发你。"
            ),
            AIReplyVariant(
                kind: .formal,
                emotion: .neutral,
                text: "收到，预算版本今晚整理完毕，明日上午发送给您。"
            ),
            AIReplyVariant(
                kind: .playful,
                emotion: .playful,
                text: "行嘞～预算表这就去梳妆打扮，明早准时上桌！"
            )
        ]
    }
}

// MARK: - Shared helpers

private extension WhatsNewDemoScenario.Language {
    var locale: Locale {
        self == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans")
    }

    var uiLanguage: AppUILanguage {
        self == .en ? .english : .chinese
    }
}

private extension KeyboardState {
    func prepareConceptKeyboard() {
        surface = .voice
        aiServiceAvailable = true
        micDisabled = false
        usesIPadLayoutMetrics = false
        micVoiceAvailability = .ready
        aiSession.enter()
    }
}

private extension View {
    /// Keyboard metrics follow the real screen width instead of a fixed 390 pt.
    func conceptKeyboardWidth(_ state: KeyboardState) -> some View {
        onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            state.layoutWidth = width
        }
    }
}

private func pause(_ seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
}
#endif
