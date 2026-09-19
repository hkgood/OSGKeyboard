// ClipboardHistoryDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// What's New 1.7.0 recording host. Voice chrome + clipboard panel are the
// **real** extension views (`KeyboardTopControls`, `RecordButton`,
// `KeyboardTranslationMenuButton`, `ClipboardHistoryPanelView`, …) driven by
// scripted `KeyboardState`. Launch with `--clipboard-demo`.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct ClipboardHistoryDemoView: View {
    private enum Layout {
        static let micSize: CGFloat = 121
        static let undoSize: CGFloat = 52
        static let micToButtonGap: CGFloat = 8
        static let actionClusterTopGap: CGFloat = Spacing.xl
        static let micUpwardAdjustment: CGFloat =
            (actionClusterTopGap - micToButtonGap) / 2
    }

    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    // `AIKeyboardView` ranks its skill row off `ClipboardHistoryStore.shared`
    // and `ClipboardSemanticRankingStore.shared`. Driving a private store here
    // would leave the row to be faked, which is exactly what made earlier takes
    // diverge from the shipping UI.
    @ObservedObject private var history = ClipboardHistoryStore.shared
    @ObservedObject private var ranking = ClipboardSemanticRankingStore.shared

    @Environment(\.colorScheme) private var colorScheme
    /// Mirrors the chat host for `--preview-fullscreen` recordings.
    @State private var hostDraft: String = ""
    /// Closing beat: hand the copied text to the real AI skill row.
    @State private var showsSkills = false

    private var palette: ThemePalette {
        colorScheme == .dark ? Palette.dark : Palette.light
    }

    var body: some View {
        ZStack {
            if FeaturePreviewFlags.isFullscreen {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            } else {
                OSGColor.demoBackground.ignoresSafeArea()
            }
            VStack(spacing: 0) {
                if FeaturePreviewFlags.isFullscreen {
                    // Chinese-only recording — see the `zh-Hans` locale pin on
                    // this view's body; the sample conversation has no English
                    // variant, so the host chrome stays Chinese to match.
                    FeaturePreviewHostDocument(
                        kind: .messages,
                        title: "信息",
                        language: .zh,
                        text: hostDraft,
                        incoming: Self.incomingMessage
                    )
                } else {
                    Spacer(minLength: 0)
                }
                keyboardChrome
                    .background(palette.background.ignoresSafeArea(edges: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(palette.divider)
                            .frame(height: 0.5)
                    }
            }
        }
        .environment(\.themePalette, palette)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .preferredColorScheme(.light)
        .task { await runTimeline() }
    }

    // MARK: - Real keyboard chrome (voice + clipboard overlay)

    private var keyboardChrome: some View {
        ZStack {
            if showsSkills {
                // Real unified AI surface — the skill row owns「一键回复」.
                AIKeyboardView(state: state, typing: typing, onInsert: { _ in })
                    .transition(.opacity)
            } else {
                voiceSurface
                    .opacity(state.clipboardOverlay == .none ? 1 : 0)
                    .allowsHitTesting(state.clipboardOverlay == .none)
            }

            if state.clipboardOverlay == .historyPanel {
                ClipboardHistoryPanelView(
                    history: history,
                    onClose: { state.clipboardOverlay = .none },
                    onClear: { history.clearAll() },
                    onInsert: { text in
                        state.clipboardSuggestionText = text
                        state.clipboardOverlay = .none
                    },
                    onDelete: { history.remove(id: $0) },
                    pastePermissionHint: nil
                )
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
        .frame(maxWidth: .infinity)
        .frame(height: KeyboardChromeLayout.totalHeight)
        .padding(.bottom, 24)
        .environment(\.themePalette, palette)
    }

    private var voiceSurface: some View {
        VStack(spacing: 0) {
            topBar.frame(height: KeyboardTopBarMetrics.height)
            Color.clear.frame(height: Layout.actionClusterTopGap)
            Spacer(minLength: 0)
            micActionRow
        }
        .frame(maxWidth: KeyboardChromeLayout.voiceContentMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var topBar: some View {
        HStack(spacing: Spacing.xs) {
            if let suggestion = state.clipboardSuggestionText, !suggestion.isEmpty {
                ClipboardSuggestionBar(
                    text: suggestion,
                    onInsert: {},
                    onDismiss: { state.clipboardSuggestionText = nil }
                )
            } else {
                KeyboardBrandLogo(action: {})
                Spacer(minLength: 0)
                KeyboardTopControls(
                    state: state,
                    typing: typing,
                    palette: palette,
                    onInsert: { _ in }
                )
            }
        }
        .padding(.horizontal, KeyboardTopBarMetrics.nestedHorizontalInset)
    }

    private var micActionRow: some View {
        VStack(spacing: Layout.micToButtonGap) {
            HStack(spacing: 0) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        demoKey(
                            systemName: "arrow.uturn.backward",
                            width: Layout.undoSize,
                            height: Layout.undoSize
                        )
                        .offset(y: -Layout.micUpwardAdjustment)
                    }

                RecordButton(
                    phase: .idleReady,
                    level: 0,
                    isEnabled: true,
                    onToggle: {},
                    onPressingChanged: { _ in },
                    onEditLongPressBegan: nil
                )
                .frame(width: Layout.micSize, height: Layout.micSize)
                .offset(y: -Layout.micUpwardAdjustment)

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .trailing) {
                        KeyboardTranslationMenuButton(
                            palette: palette,
                            targetLocaleId: TranslationLanguageCatalog.offLocaleId,
                            onSelect: { _ in }
                        )
                        .equatable()
                        .frame(width: Layout.undoSize, height: Layout.undoSize)
                        .offset(y: -Layout.micUpwardAdjustment)
                    }
            }
            .frame(height: Layout.micSize)

            GeometryReader { proxy in
                let widths = KeyboardChromeLayout.actionKeyWidthsWithoutGlobe(
                    availableWidth: proxy.size.width
                )
                HStack(spacing: KeyboardChromeLayout.actionKeySpacing) {
                    demoKey(systemName: "delete.backward", width: widths.side)
                    demoKey(
                        title: ExtL10n.string("common.newline"),
                        width: widths.center
                    )
                    demoKey(spaceStyle: true, width: widths.side2)
                }
            }
            .frame(height: KeyboardChromeLayout.actionKeyHeight)
        }
        .padding(.horizontal, KeyboardChromeLayout.horizontalInset)
    }

    /// Same chrome as Ext `RectangularToolbarButton` / native key surface.
    private func demoKey(
        systemName: String? = nil,
        title: String? = nil,
        spaceStyle: Bool = false,
        width: CGFloat,
        height: CGFloat = KeyboardChromeLayout.actionKeyHeight
    ) -> some View {
        NativeKeyboardKeySurface(
            isPressed: false,
            fill: NativeKeyboardKeyColors.fill(for: colorScheme),
            pressedFill: NativeKeyboardKeyColors.pressedFill(for: colorScheme),
            border: palette.divider,
            cornerRadius: KeyboardChromeLayout.actionKeyCornerRadius
        ) {
            Group {
                if spaceStyle {
                    Capsule()
                        .fill(NativeKeyboardKeyColors.text(for: colorScheme).opacity(0.22))
                        .frame(width: 31, height: 4)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
                } else if let title {
                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
                }
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Timeline

    private func runTimeline() async {
        prepareState()
        seedHistory()

        // Hold on voice idle so translation + clipboard chip are readable.
        try? await sleep(2.2)

        withAnimation(.easeInOut(duration: 0.2)) {
            state.clipboardOverlay = .historyPanel
        }
        try? await sleep(2.0)

        if let head = history.newestEntry {
            withAnimation(.easeInOut(duration: 0.25)) {
                state.clipboardSuggestionText = head.text
                state.clipboardOverlay = .none
            }
        }
        try? await sleep(2.4)

        guard FeaturePreviewFlags.isFullscreen else { return }
        await runReplyBeat()
    }

    /// Reply styles are separate skills in the row rather than variants offered
    /// after one tap, so the beat runs the same copied message through two of
    /// them back to back — that is what "多个风格的回复" looks like in the real UI.
    ///
    /// Which chips appear is decided by `ClipboardSkillSemanticRanker`, not by
    /// this file: production caps specialised reply skills at two alongside the
    /// generic 回复, so hand-picking a longer row produced a keyboard that could
    /// never exist. The beat therefore taps whatever the ranker surfaced.
    private func runReplyBeat() async {
        AIKeyboardView.debugSkipsLongPressCoach = true
        AIKeyboardView.debugPreviewSkills = nil
        state.aiServiceAvailable = true
        state.surface = .ai
        state.aiSession.enter()
        state.pendingClipboardSkillID = nil
        withAnimation(.easeInOut(duration: 0.3)) {
            showsSkills = true
        }

        let skills = await rankedReplySkills()
        try? await sleep(0.85)

        guard let generic = skills.first(where: {
            $0.id == AIClipboardSkillCatalog.replyID
        }) else { return }
        await runReplySkill(
            skill: generic,
            answer: "好的，预算版我整理一下，明天上午发你。"
        )
        state.pendingClipboardSkillID = nil
        try? await sleep(0.6)

        // Second style: whatever specialised reply the ranker actually offered.
        if let specialised = skills.first(where: {
            $0.supportsReplyStyle && $0.id != AIClipboardSkillCatalog.replyID
        }) {
            await runReplySkill(
                skill: specialised,
                answer: Self.answer(for: specialised.id)
            )
        }
        // End back on the skill row so the card loops without a jump.
        state.pendingClipboardSkillID = nil
        try? await sleep(0.25)
    }

    /// Runs the real semantic analysis the keyboard uses, then reports the row
    /// it produced so the beat can tap chips that are genuinely on screen.
    private func rankedReplySkills() async -> [AIClipboardSkill] {
        guard let newest = history.newestEntry else { return [] }
        ranking.analyze(newest)
        // The analyzer runs off the main actor; wait for its snapshot rather
        // than racing it, or the row falls back to a lone 回复 chip.
        for _ in 0..<40 {
            if ranking.snapshot?.entryID == newest.id { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let snapshot = ranking.snapshot, snapshot.entryID == newest.id else {
            return state.clipboardSkillCatalog.filter {
                $0.id == AIClipboardSkillCatalog.replyID
            }
        }
        return ClipboardSkillSemanticRanker.recommended(
            skills: state.clipboardSkillCatalog,
            sourceText: newest.text,
            analysis: snapshot.analysis,
            uiLanguage: state.uiLanguage,
            limit: 5
        )
    }

    /// Demo copy per reply style. Keyed by skill so the answer matches whatever
    /// chip the ranker put in the row.
    private static func answer(for skillID: String) -> String {
        switch skillID {
        case AIClipboardSkillCatalog.playfulReplyID:
            return "行嘞，预算表这就去梳妆打扮，明早准时上桌。"
        case AIClipboardSkillCatalog.businessReplyID:
            return "收到，预算版本我今晚整理完，明日上午发送给您。"
        case AIClipboardSkillCatalog.empathyReplyID:
            return "理解，这版确实等着用。我加紧整理，明早一定发你。"
        case AIClipboardSkillCatalog.acceptTaskID:
            return "好的，这件事我接了，明天上午把预算版发你。"
        case AIClipboardSkillCatalog.clarifyRequestID:
            return "没问题，你要的是含人力成本的那版，还是只要采购部分？"
        default:
            return "好的，我整理一下，明天上午发你。"
        }
    }

    /// One tap on a reply-style chip: the row gives way to the thinking state,
    /// the answer streams in, then it is offered for insertion.
    private func runReplySkill(skill: AIClipboardSkill, answer: String) async {
        // Drives the real generating copy (falls through to「AI 正在思考…」,
        // same as a production skill run).
        state.pendingClipboardSkillID = skill.id

        // `beginGenerating` (and every later step) is guarded on
        // `activeUtteranceID`, which only `beginPreparing` sets — skipping it
        // makes the whole sequence a silent no-op and the keyboard never
        // shows an answer.
        let utteranceID = UUID()
        state.aiSession.enter()
        state.aiSession.beginPreparing(utteranceID: utteranceID)
        state.aiSession.beginGenerating(question: "", utteranceID: utteranceID)
        try? await sleep(0.2)

        let chars = Array(answer)
        var index = 0
        while index < chars.count {
            index = min(chars.count, index + 3)
            state.aiSession.receivePartialAnswer(
                String(chars[..<index]),
                utteranceID: utteranceID
            )
            try? await sleep(0.04)
        }
        state.aiSession.receiveAnswer(answer, utteranceID: utteranceID)
        try? await sleep(0.45)

        state.aiSession.markAnswerInserted(offersSend: true)
        hostDraft = answer
        try? await sleep(0.2)
    }

    private func prepareState() {
        state.surface = .voice
        state.micVoiceAvailability = .ready
        state.layoutWidth = 390
        state.usesIPadLayoutMetrics = false
        state.showsSystemGlobeKey = false
        // `AIKeyboardView.showsClipboardSkills` gates on this — without it the
        // real skill row never appears no matter what the ranker returns.
        state.clipboardHistoryEnabled = true
        state.clipboardCandidateBarEnabled = true
        state.clipboardOverlay = .none
        state.clipboardSuggestionText = nil
        state.openClipboardPanel = {
            state.clipboardOverlay = .historyPanel
        }
        state.dismissClipboardOverlay = {
            state.clipboardOverlay = .none
        }
        state.insertClipboardText = { text in
            state.clipboardSuggestionText = text
            state.clipboardOverlay = .none
        }
    }

    private func seedHistory() {
        history.clearAll()
        _ = history.ingest(rawText: "订单号 OSG-20260811-8842", changeCount: 3)
        _ = history.ingest(rawText: "https://osglab.com", changeCount: 2)
        _ = history.ingest(rawText: Self.incomingMessage, changeCount: 1)
        history.reload()
    }

    /// The message the clip replies to. Copying it is what puts the reply
    /// skills in the row, so it has to be the newest clipboard entry.
    static let incomingMessage = "方案我看了，明天能不能把预算那一版也发我？" 

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 2.4 * 1_000_000_000))
    }
}
#endif
