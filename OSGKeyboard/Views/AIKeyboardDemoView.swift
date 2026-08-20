// AIKeyboardDemoView.swift
// OSGKeyboard · Main App (DEBUG-only)
//
// What's New recording host. Uses the **real** AI Agent settings page and the
// **real** unified `AIKeyboardView` (compiled into the app target), driven by a
// scripted `KeyboardState` — no ASR / LLM. Launch with `--ai-demo` and optional
// `--whats-new-lang=zh|en`.

#if DEBUG
import OSGKeyboardShared
import SwiftUI

struct AIKeyboardDemoView: View {
    private enum Scene: Equatable {
        case settings
        case keyboard
    }

    @StateObject private var config = ProviderConfig.shared
    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()

    @State private var scene: Scene = .settings
    @State private var levelTick = 0.35

    init() {
        AIKeyboardView.debugSkipsLongPressCoach = true
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            // Both scenes sit on the bottom band so what's-new crop matches Ext chrome.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                switch scene {
                case .settings:
                    ThemedRoot {
                        NavigationStack {
                            AIAgentSettingsView(config: config)
                        }
                    }
                    .preferredColorScheme(.light)
                    .frame(maxWidth: .infinity)
                    // Keep under what's-new crop (~327 pt visible at 3x).
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                case .keyboard:
                    AIKeyboardView(
                        state: state,
                        typing: typing,
                        onInsert: { _ in }
                    )
                    .background(Palette.light.background.ignoresSafeArea(edges: .bottom))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .environment(\.locale, language == .en ? Locale(identifier: "en") : Locale(identifier: "zh-Hans"))
        .task { await runTimeline() }
        .onDisappear {
            AIKeyboardView.debugSkipsLongPressCoach = false
        }
    }

    // MARK: - Scripted timeline (real view models)

    private func runTimeline() async {
        prepareKeyboardState()
        config.uiLanguage = language == .en ? .english : .chinese
        config.aiResponseLength = .medium

        try? await sleep(2.4)

        withAnimation(.easeInOut(duration: 0.35)) {
            scene = .keyboard
        }
        try? await sleep(1.2)

        let utteranceID = UUID()
        state.aiSession.enter()
        state.aiSession.beginPreparing(utteranceID: utteranceID)
        try? await sleep(0.35)
        state.aiSession.beginListening(utteranceID: utteranceID)
        state.level = 0.4
        for _ in 0..<8 {
            try? await sleep(0.2)
            levelTick = Double.random(in: 0.25...0.9)
            state.level = levelTick
            state.aiSession.updateTranscript(question, utteranceID: utteranceID)
        }

        state.aiSession.beginRecognizing(utteranceID: utteranceID)
        try? await sleep(0.55)
        state.aiSession.beginGenerating(question: question, utteranceID: utteranceID)
        try? await sleep(0.7)

        // Progressive draft so the real answer area updates like production.
        let chars = Array(answer)
        var index = 0
        let step = 4
        while index < chars.count {
            index = min(index + step, chars.count)
            state.aiSession.receivePartialAnswer(
                String(chars[..<index]),
                utteranceID: utteranceID
            )
            try? await sleep(0.05)
        }
        state.aiSession.receiveAnswer(answer, utteranceID: utteranceID)
        // Hold the explicit-insert review state long enough for screen capture
        // and for viewers to read the answer before the demo advances.
        try? await sleep(3.0)

        state.aiSession.markAnswerInserted(offersSend: true)
        try? await sleep(1.1)
        state.aiSession.markAnswerSent()
        try? await sleep(1.6)
    }

    private func prepareKeyboardState() {
        state.surface = .voice
        state.aiServiceAvailable = true
        state.micDisabled = false
        state.layoutWidth = 390
        state.usesIPadLayoutMetrics = false
        state.micVoiceAvailability = .ready
        state.aiSession.enter()
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

    private var question: String {
        language == .en
            ? "Where should I go this weekend?"
            : "周末去哪儿玩比较合适？"
    }

    private var answer: String {
        language == .en
            ? "Try a nearby town day trip: walk through a park or old street, stop at a café, then have a local dinner."
            : "可以去近郊走走：上午逛古镇或公园，下午找一家口碑好的咖啡馆休息，傍晚再吃顿当地特色菜。"
    }

    /// Slow-mo for screenshot-sequence recording.
    private func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 2.4 * 1_000_000_000))
    }
}
#endif
