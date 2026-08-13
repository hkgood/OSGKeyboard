// WhatsNewDemoDriver.swift
// OSGKeyboard · Keyboard Extension (DEBUG-only)
//
// Plays a scripted What's New timeline on the **real** keyboard surface while
// a Notes-like host sits underneath. Mutates the host document via the
// textDocumentProxy so the clip shows a closed loop (insert / replace).

#if DEBUG
import Foundation
import OSGKeyboardShared

@MainActor
enum WhatsNewDemoDriver {
    private static var running = false
    private static var activeTask: Task<Void, Never>?

    /// Document mutations + Return for AI “发送”.
    struct HostHooks {
        var insertText: (String) -> Void
        var deleteBackward: () -> Void
        var contextBeforeInput: () -> String?
        var performReturn: () -> Void
    }

    /// Keyboard extensions outlive host relaunches — always allow a fresh arm.
    static func resetForNewPresentation() {
        activeTask?.cancel()
        activeTask = nil
        running = false
        WhatsNewDemoScenario.finishPlaying()
    }

    static func startIfNeeded(state: KeyboardState, host: HostHooks) {
        // Peek first so a brief appear/disappear does not burn the arm.
        guard WhatsNewDemoScenario.peek() != nil else { return }
        // A still-running timeline from a previous host launch must not block
        // the next What's New recording.
        if running {
            resetForNewPresentation()
        }
        running = true
        activeTask = Task { @MainActor in
            // Wait for first layout / surface mount over the host.
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else {
                running = false
                return
            }
            guard let armed = WhatsNewDemoScenario.consume() else {
                running = false
                return
            }
            OSGDiag.log(
                "WhatsNewDemo start scenario=\(armed.scenario.rawValue) lang=\(armed.language.rawValue)",
                category: "boot"
            )
            polishDemoChrome(state)
            switch armed.scenario {
            case .edit:
                await runEdit(
                    state: state,
                    host: host,
                    original: armed.seedText,
                    language: armed.language
                )
            case .ai:
                await runAI(state: state, host: host, language: armed.language)
            case .clipboard:
                await runClipboard(state: state, host: host, language: armed.language)
            }
            if !Task.isCancelled {
                WhatsNewDemoScenario.finishPlaying()
            }
            running = false
            activeTask = nil
        }
    }

    // MARK: - Edit last input

    private static func runEdit(
        state: KeyboardState,
        host: HostHooks,
        original: String,
        language: WhatsNewDemoScenario.Language
    ) async {
        let edited = language == .en
            ? "Hi everyone — we'll hold a planning discussion in Conference Room A at 3pm tomorrow. Please be on time."
            : "各位好，明天下午三点在 A 会议室召开方案讨论会，请准时参加。"
        let reference = EditableInputReference(
            displayText: original,
            insertedText: original,
            postInsertionFingerprint: nil,
            extensionInstanceID: UUID()
        )
        let source = EditSessionSource(reference: reference)
        let review = EditReview(
            source: source,
            resultText: edited,
            utteranceID: UUID()
        )

        state.surface = .voice
        state.editCanReplaceOriginal = true
        state.phase = .idle
        ClipboardHistoryStore.shared.clearAll()
        clearClipboardChrome(state)
        polishDemoChrome(state)

        // Brief idle so the host note + voice mic are visible together.
        try? await sleep(1.0)

        state.editSession = .listening(source)
        state.lastTranscript = ExtL10n.string("keyboard.edit.status.listening")
        state.level = 0.45
        for _ in 0..<4 {
            try? await sleep(0.28)
            state.level = Double.random(in: 0.25...0.85)
            polishDemoChrome(state)
        }

        state.editSession = .processing(source)
        state.lastTranscript = ExtL10n.string("keyboard.edit.status.processing")
        try? await sleep(1.0)

        state.editSession = .review(review)
        state.lastTranscript = ExtL10n.string("keyboard.edit.status.review")
        try? await sleep(2.4)

        state.editSession = .applying(review)
        state.lastTranscript = ExtL10n.string("keyboard.edit.status.applying")
        // Replace host document so the clip closes the loop.
        replaceHostText(from: original, to: edited, host: host)
        try? await sleep(1.2)

        state.editSession = .inactive
        state.editCanReplaceOriginal = false
        state.phase = .idle
        state.lastTranscript = ""
        clearClipboardChrome(state)
        polishDemoChrome(state)
        try? await sleep(1.2)
    }

    // MARK: - AI keyboard

    private static func runAI(
        state: KeyboardState,
        host: HostHooks,
        language: WhatsNewDemoScenario.Language
    ) async {
        let question = language == .en
            ? "Where should I go this weekend?"
            : "周末去哪儿玩比较合适？"
        let answer = language == .en
            ? "Try a nearby town day trip: morning walk in a park or old street, afternoon café, then a local dinner."
            : "可以去近郊走走：上午逛古镇或公园，下午找一家口碑好的咖啡馆休息，傍晚再吃顿当地特色菜。"

        state.surface = .ai
        state.aiServiceAvailable = true
        ClipboardHistoryStore.shared.clearAll()
        clearClipboardChrome(state)
        polishDemoChrome(state)
        // Chat host uses returnKeyType=.send; keep role locked for the clip.
        state.returnKeyRole = .send
        state.aiSession.enter()
        try? await sleep(0.9)

        let utteranceID = UUID()
        state.aiSession.beginPreparing(utteranceID: utteranceID)
        try? await sleep(0.25)
        state.aiSession.beginListening(utteranceID: utteranceID)
        state.level = 0.4
        for _ in 0..<6 {
            try? await sleep(0.18)
            state.level = Double.random(in: 0.25...0.9)
            state.aiSession.updateTranscript(question, utteranceID: utteranceID)
            polishDemoChrome(state)
        }

        state.aiSession.beginRecognizing(utteranceID: utteranceID)
        try? await sleep(0.4)
        state.aiSession.beginGenerating(question: question, utteranceID: utteranceID)
        try? await sleep(0.45)

        let chars = Array(answer)
        var index = 0
        while index < chars.count {
            index = min(chars.count, index + 5)
            let draft = String(chars.prefix(index))
            state.aiSession.receivePartialAnswer(draft, utteranceID: utteranceID)
            try? await sleep(0.1)
        }
        state.aiSession.receiveAnswer(answer, utteranceID: utteranceID)
        polishDemoChrome(state)
        try? await sleep(1.3)

        // Insert on a new line so seed + answer stay readable in the composer.
        host.insertText("\n" + answer)
        state.aiSession.markAnswerInserted(offersSend: true)
        polishDemoChrome(state)
        try? await sleep(1.1)

        state.aiSession.markAnswerSent()
        host.performReturn()
        // Stay on AI surface so the “已发送” beat is not buried by voice chrome.
        state.surface = .ai
        clearClipboardChrome(state)
        polishDemoChrome(state)
        try? await sleep(1.4)
    }

    // MARK: - Clipboard history

    private static func runClipboard(
        state: KeyboardState,
        host: HostHooks,
        language: WhatsNewDemoScenario.Language
    ) async {
        let samples = language == .en
            ? [
                "Meeting at 3pm tomorrow",
                "Room moved to Building A, 3F",
                "Bring the clicker and the deck"
            ]
            : [
                "明天下午三点开会",
                "会议室改到 A 栋 3 楼",
                "请带上投影笔和方案文档"
            ]
        let store = ClipboardHistoryStore.shared
        store.clearAll()
        for text in samples.reversed() {
            _ = store.ingest(rawText: text, changeCount: Int.random(in: 1...9_999))
        }
        store.reload()

        // Persist flags so AppGroupPersistor cannot flip history off mid-demo.
        if let defaults = AppGroup.defaultsIfAvailable {
            defaults.set(true, forKey: AppGroupConfiguration.Keys.clipboardHistoryEnabled)
            defaults.set(true, forKey: AppGroupConfiguration.Keys.clipboardCandidateBarEnabled)
            defaults.synchronize()
        }

        state.surface = .voice
        state.clipboardHistoryEnabled = true
        state.clipboardCandidateBarEnabled = true
        state.phase = .idle
        state.clipboardOverlay = .none
        polishDemoChrome(state)
        // Suggestion strip first (matches the docs copy).
        state.clipboardSuggestionText = samples[0]
        state.clipboardSuggestionChangeCount = 1

        try? await sleep(1.2)
        polishDemoChrome(state)

        state.clipboardOverlay = .historyPanel
        try? await sleep(2.6)
        polishDemoChrome(state)

        // Tap-to-insert: close panel + write into the host “待办：” field.
        state.clipboardOverlay = .none
        host.insertText(samples[0])
        polishDemoChrome(state)
        try? await sleep(0.9)

        // Leave a fresh suggestion strip visible for the next copy cue.
        state.clipboardSuggestionText = samples[1]
        state.clipboardSuggestionChangeCount = 2
        // Hold suggestion with chrome locked clean (no Flow warning flash).
        for _ in 0..<8 {
            polishDemoChrome(state)
            try? await sleep(0.2)
        }
    }

    // MARK: - Host helpers

    private static func polishDemoChrome(_ state: KeyboardState) {
        state.micDisabledHint = ""
        state.micVoiceAvailability = .ready
    }

    private static func clearClipboardChrome(_ state: KeyboardState) {
        state.clipboardOverlay = .none
        state.clipboardSuggestionText = nil
        state.clipboardSuggestionChangeCount = nil
    }

    private static func replaceHostText(
        from original: String,
        to edited: String,
        host: HostHooks
    ) {
        // Prefer deleting only the seed suffix so we don't wipe unrelated text.
        let before = host.contextBeforeInput() ?? ""
        let deleteCount: Int
        if before.hasSuffix(original) {
            deleteCount = original.count
        } else if !before.isEmpty {
            deleteCount = before.count
        } else {
            deleteCount = original.count
        }
        for _ in 0..<deleteCount {
            host.deleteBackward()
        }
        host.insertText(edited)
    }

    /// ~1.6× slow-mo for screen recording readability (30 fps source).
    private static func sleep(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1.6 * 1_000_000_000))
    }
}
#endif
