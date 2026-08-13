// AIKeyboardCoordinator.swift
// OSGKeyboard · Keyboard Extension
//
// Owns the temporary AI-mode UI state. Audio, ASR, and LLM work remain in the
// shared Flow transport and host app; this coordinator never performs network
// work and never inserts an answer before explicit user confirmation.

import Foundation
import OSGKeyboardShared

@MainActor
final class AIKeyboardCoordinator {
    private let state: KeyboardState
    private let flow: KeyboardFlowCoordinator
    private let insertAnswer: (AIAnswer) -> Bool
    private let performReturn: () -> Void

    init(
        state: KeyboardState,
        flow: KeyboardFlowCoordinator,
        insertAnswer: @escaping (AIAnswer) -> Bool,
        performReturn: @escaping () -> Void
    ) {
        self.state = state
        self.flow = flow
        self.insertAnswer = insertAnswer
        self.performReturn = performReturn
    }

    func beginNewPresentation() {
        endConversationIfNeeded()
        state.aiSession.enter()
    }

    func enterIfNeeded() {
        guard !state.aiSession.isActive else { return }
        state.aiSession.enter()
    }

    func leave() {
        if state.aiSession.isBusy {
            flow.cancelAIRecording()
        }
        endConversationIfNeeded()
        state.aiSession.leave()
    }

    func toggleMicrophone() {
        switch state.aiSession.phase {
        case .listening:
            guard let utteranceID = state.aiSession.activeUtteranceID else { return }
            state.aiSession.beginRecognizing(utteranceID: utteranceID)
            flow.stopAIRecording()
        case .idle, .ready, .awaitingSend, .inserted, .sent, .failed:
            enterIfNeeded()
            guard let conversationID = state.aiSession.conversationID else { return }
            let disposition = flow.beginAIRecording(conversationID: conversationID)
            if case .rejected(let rejection) = disposition {
                state.aiSession.fail(message(for: rejection), utteranceID: nil)
            }
        case .inactive:
            enterIfNeeded()
            toggleMicrophone()
        case .preparing, .recognizing, .generating:
            break
        }
    }

    /// Tap a clipboard skill chip: same fail-closed material path as hint cards.
    func submitClipboardSkill(_ skill: AIClipboardSkill) {
        guard canAcceptIdleSubmit else { return }
        enterIfNeeded()
        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: AIHintLocaleResolver.packLocale(),
            translationTargetLocaleId: state.translationTargetLocaleId
        )
        let resolution = AIClipboardPrompt.resolve(
            instruction: instruction,
            material: ClipboardHistoryStore.shared.newestAIHintEligibleEntry()?.text
        )
        submitResolvedPrompt(resolution)
    }

    /// Tap an idle hint card: resolve its material, skip the mic, ask the host.
    func submitHintCard(_ card: AIHintCard) {
        guard canAcceptIdleSubmit else { return }
        enterIfNeeded()
        let resolution = AIHintPool.resolvePrompt(
            for: card,
            clipboardText: ClipboardHistoryStore.shared.newestAIHintEligibleEntry()?.text
        )
        submitResolvedPrompt(resolution)
    }

    private var canAcceptIdleSubmit: Bool {
        switch state.aiSession.phase {
        case .inactive, .idle, .failed:
            return true
        case .preparing, .listening, .recognizing, .generating,
             .ready, .awaitingSend, .inserted, .sent:
            return false
        }
    }

    private func submitResolvedPrompt(_ resolution: AIClipboardPrompt.Resolution) {
        guard case .ready(let prompt) = resolution else {
            // The clipboard window closed between rendering and this tap.
            state.aiSession.fail(
                ExtL10n.string("keyboard.ai.error.clipboardUnavailable"),
                utteranceID: nil
            )
            return
        }
        guard let conversationID = state.aiSession.conversationID else { return }
        let disposition = flow.submitAIQuestion(
            text: prompt,
            conversationID: conversationID
        )
        if case .rejected(let rejection) = disposition {
            state.aiSession.fail(message(for: rejection), utteranceID: nil)
        }
    }

    func cancel() {
        guard state.aiSession.isBusy else { return }
        flow.cancelAIRecording()
        state.aiSession.cancelCurrentWork()
    }

    func sendLatestAnswer() {
        if state.aiSession.canInsert, let answer = state.aiSession.answer {
            guard insertAnswer(answer) else { return }
            state.aiSession.markAnswerInserted(
                offersSend: state.returnKeyRole == .send
            )
        } else if state.aiSession.canSend {
            state.aiSession.markAnswerSent()
            // Let the host consume the inserted answer before issuing Return.
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.performReturn()
            }
        }
    }

    func utterancePrepared(_ utteranceID: UUID) {
        state.aiSession.beginPreparing(utteranceID: utteranceID)
    }

    func recordingStarted(_ utteranceID: UUID) {
        state.aiSession.beginListening(utteranceID: utteranceID)
    }

    func recognitionStarted(_ utteranceID: UUID) {
        state.aiSession.beginRecognizing(utteranceID: utteranceID)
    }

    func generatingStarted(_ utteranceID: UUID) {
        state.aiSession.beginGenerating(question: "", utteranceID: utteranceID)
    }

    func receiveTranscript(
        _ transcript: String,
        utteranceID: UUID,
        status: FlowResult.Status
    ) {
        if AIClipboardPrompt.isInternalPrompt(transcript) {
            if status == .rawReady {
                state.aiSession.beginGenerating(question: "", utteranceID: utteranceID)
            }
            return
        }
        state.aiSession.updateTranscript(transcript, utteranceID: utteranceID)
        if status == .rawReady {
            state.aiSession.beginGenerating(
                question: transcript,
                utteranceID: utteranceID
            )
        }
    }

    func receivePartialAnswer(_ draft: String, utteranceID: UUID) {
        state.aiSession.receivePartialAnswer(draft, utteranceID: utteranceID)
    }

    func receive(result: FlowResult) {
        guard result.resolvedUtteranceMode == .aiQuestion else {
            return
        }
        guard result.aiConversationID == state.aiSession.conversationID,
              let answer = result.text,
              !answer.isEmpty else {
            state.aiSession.fail(
                ExtL10n.string("keyboard.ai.error.requestFailed"),
                utteranceID: result.utteranceId
            )
            return
        }
        state.aiSession.receiveAnswer(answer, utteranceID: result.utteranceId)
    }

    func fail(_ message: String, utteranceID: UUID?) {
        state.aiSession.fail(message, utteranceID: utteranceID)
    }

    private func endConversationIfNeeded() {
        guard let conversationID = state.aiSession.conversationID else { return }
        flow.endAIConversation(conversationID)
    }

    private func message(for rejection: FlowUtteranceStartRejection) -> String {
        switch rejection {
        case .onboardingIncomplete:
            return ExtL10n.string("keyboard.hint.finishSetupInApp")
        case .missingAPIKey:
            return ExtL10n.string("keyboard.ai.error.missingAPIKey")
        case .noFullAccess:
            return ExtL10n.string("keyboard.error.fullAccessRequired")
        case .appGroupUnavailable:
            return ExtL10n.string("keyboard.error.appGroupCommunication")
        case .hostUnavailable:
            return ExtL10n.string("keyboard.flow.hostDisconnected")
        case .pipelineBusy:
            return ExtL10n.string("keyboard.ai.error.pipelineBusy")
        }
    }
}
