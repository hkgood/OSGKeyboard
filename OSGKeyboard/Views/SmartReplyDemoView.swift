// SmartReplyDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// What's New 2.1.0 recording host for the auto-triggered smart-reply surface.
// Copying a message surfaces the real `replyVariantsSurface` on the unified
// `AIKeyboardView` with Ordinary / Formal / Playful choices. No ASR, no LLM,
// no network — the session is scripted straight into the reply-variant state,
// so the frame is the same view the shipping keyboard shows.
// Launch with `--smart-reply-demo`, optional `--whats-new-lang=zh|en`.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct SmartReplyDemoView: View {
    @StateObject private var config = ProviderConfig.shared
    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AIKeyboardView(state: state, typing: typing, onInsert: { _ in })
                .background(Palette.light.background)
        }
        .background(OSGColor.demoBackground.ignoresSafeArea())
        .environment(
            \.locale,
            language == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans")
        )
        .preferredColorScheme(.light)
        .task { await runTimeline() }
    }

    /// Copy → brief thinking → the three personalized reply choices reveal and
    /// hold. Mirrors the shipping auto-reply path, which populates the same
    /// `aiSession.replyVariants` the coordinator fills from a live request.
    private func runTimeline() async {
        prepareState()
        try? await sleep(1.0)

        let utteranceID = UUID()
        state.aiSession.beginPreparing(utteranceID: utteranceID)
        state.aiSession.beginGenerating(question: "", utteranceID: utteranceID)
        try? await sleep(1.1)

        state.aiSession.receiveReplyVariants(
            Self.variants(language: language),
            utteranceID: utteranceID
        )
        try? await sleep(6.0)
    }

    private func prepareState() {
        config.uiLanguage = language == .en ? .english : .chinese
        state.surface = .voice
        state.aiServiceAvailable = true
        state.micDisabled = false
        state.layoutWidth = 390
        state.usesIPadLayoutMetrics = false
        state.clipboardHistoryEnabled = true
        state.clipboardSuggestionText = language == .en
            ? "Read the proposal — can you also send me the budget version tomorrow?"
            : "方案我看了，明天能不能把预算那一版也发我？"
        state.aiSession.enter()
    }

    private static func variants(
        language: WhatsNewDemoScenario.Language
    ) -> [AIReplyVariant] {
        if language == .en {
            return [
                AIReplyVariant(
                    kind: .ordinary,
                    emotion: .neutral,
                    text: "Sure, I'll put the budget version together and send it over tomorrow morning."
                ),
                AIReplyVariant(
                    kind: .formal,
                    emotion: .neutral,
                    text: "Received. I'll finalize the budget version tonight and send it to you tomorrow morning."
                ),
                AIReplyVariant(
                    kind: .playful,
                    emotion: .playful,
                    text: "You got it — the budget sheet is getting dressed up and will be on your desk first thing!"
                )
            ]
        }
        return [
            AIReplyVariant(
                kind: .ordinary,
                emotion: .neutral,
                text: "好的，我整理一下预算版，明天上午发你。"
            ),
            AIReplyVariant(
                kind: .formal,
                emotion: .neutral,
                text: "收到，预算版本我今晚整理完毕，明日上午发送给您。"
            ),
            AIReplyVariant(
                kind: .playful,
                emotion: .playful,
                text: "行嘞～预算表这就去梳妆打扮，明早准时上桌！"
            )
        ]
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

    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
#endif
