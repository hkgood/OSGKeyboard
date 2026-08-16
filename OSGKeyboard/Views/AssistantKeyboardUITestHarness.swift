#if DEBUG
import SwiftUI
import UIKit
import OSGKeyboardShared

/// Deterministic host for simulator UI tests of the real assistant keyboard.
/// It exercises gesture routing and closed UI states without requiring a
/// keyboard-extension process, microphone permission, ASR, or an LLM.
struct AssistantKeyboardUITestHarness: View {
    private enum Scenario: String {
        case idle
        case completed
        case pending
        case skillFailure
        case skills
    }

    @StateObject private var state = KeyboardState()
    @StateObject private var typing = TypingSessionController()
    @State private var configured = false
    @Environment(\.colorScheme) private var colorScheme

    init() {
        AIKeyboardView.debugSkipsLongPressCoach = true
        AIKeyboardView.debugKeepsSkillTip = true
    }

    private let scenario: Scenario = {
        let prefix = "--assistant-state="
        let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
        return raw.flatMap { Scenario(rawValue: String($0)) } ?? .idle
    }()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                AIKeyboardView(
                    state: state,
                    typing: typing,
                    onInsert: { _ in }
                )
                .background(backgroundColor)
            }
            .onAppear {
                configure(width: proxy.size.width)
            }
            .onChange(of: proxy.size.width) { _, width in
                configureLayout(width: width)
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .onDisappear {
            AIKeyboardView.debugPreviewSkills = nil
                    AIKeyboardView.debugSkipsLongPressCoach = false
                    AIKeyboardView.debugKeepsSkillTip = false
        }
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Palette.dark.background : Palette.light.background
    }

    private func configure(width: CGFloat) {
        configureLayout(width: width)
        guard !configured else { return }
        configured = true

        state.surface = .voice
        state.phase = .idle
        state.aiServiceAvailable = true
        state.micDisabled = false
        state.returnKeyRole = .send

        let keyboardState = state
        state.tapMic = { [weak keyboardState] in
            guard let keyboardState else { return }
            if case .recording = keyboardState.phase {
                keyboardState.phase = .idle
            } else {
                keyboardState.phase = .recording
            }
        }
        state.tapAIMic = { [weak keyboardState] in
            guard let keyboardState else { return }
            if keyboardState.aiSession.phase == .listening {
                if let utteranceID = keyboardState.aiSession.activeUtteranceID {
                    keyboardState.aiSession.beginRecognizing(utteranceID: utteranceID)
                }
                return
            }
            keyboardState.aiSession.enter()
            let utteranceID = UUID()
            keyboardState.aiSession.beginPreparing(utteranceID: utteranceID)
            keyboardState.aiSession.beginListening(utteranceID: utteranceID)
        }
        state.sendAssistantAction = { [weak keyboardState] in
            keyboardState?.assistantSendAvailable = false
        }
        state.undoLastInsertion = { [weak keyboardState] in
            keyboardState?.undoAvailable = false
        }
        state.beginEditLastInput = { [weak keyboardState] in
            guard let keyboardState else { return }
            let reference = EditableInputReference(
                displayText: "Original dictated input",
                insertedText: "Original dictated input",
                postInsertionFingerprint: nil,
                extensionInstanceID: UUID()
            )
            keyboardState.editSession = .listening(EditSessionSource(reference: reference))
            keyboardState.phase = .recording
        }
        state.stopEditListening = { [weak keyboardState] in
            guard let keyboardState,
                  let source = keyboardState.editSession.source else {
                return
            }
            keyboardState.editSession = .review(
                EditReview(
                    source: source,
                    resultText: "Edited dictated input",
                    utteranceID: UUID()
                )
            )
            keyboardState.phase = .processing
        }
        state.confirmEditResult = { [weak keyboardState] in
            keyboardState?.editSession = .inactive
            keyboardState?.phase = .idle
        }
        state.submitAIHint = { [weak keyboardState] _ in
            guard let keyboardState else { return }
            let utteranceID = UUID()
            keyboardState.aiSession.enter()
            keyboardState.aiSession.beginPreparing(utteranceID: utteranceID)
            keyboardState.aiSession.beginGenerating(
                question: "Deterministic hint",
                utteranceID: utteranceID
            )
        }

        switch scenario {
        case .idle:
            AIKeyboardView.debugPreviewSkills = nil
        case .completed:
            AIKeyboardView.debugPreviewSkills = nil
            state.undoAvailable = true
            state.editAvailable = true
            state.assistantSendAvailable = true
        case .pending:
            AIKeyboardView.debugPreviewSkills = nil
            let utteranceID = UUID()
            state.aiSession.enter()
            state.aiSession.beginPreparing(utteranceID: utteranceID)
            state.aiSession.receiveAnswer(
                "A retained answer that requires explicit insertion.",
                utteranceID: utteranceID
            )
            state.confirmPendingAIAnswer = { [weak keyboardState] in
                guard let keyboardState else { return }
                keyboardState.aiSession.markAnswerInserted(offersSend: true)
                keyboardState.undoAvailable = true
                keyboardState.editAvailable = true
                keyboardState.assistantSendAvailable = true
            }
            state.discardPendingAIAnswer = { [weak keyboardState] in
                keyboardState?.aiSession.discardReadyAnswer()
            }
        case .skillFailure:
            AIKeyboardView.debugPreviewSkills = nil
            state.skillTipText = "Skill failed"
        case .skills:
            AIKeyboardView.debugPreviewSkills = AIClipboardSkillCatalog.catalog
            state.undoAvailable = true
            state.editAvailable = true
        }
    }

    private func configureLayout(width: CGFloat) {
        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        state.layoutWidth = width
        state.usesIPadLayoutMetrics = isIPad
        state.showsSystemGlobeKey = isIPad
    }
}
#endif
