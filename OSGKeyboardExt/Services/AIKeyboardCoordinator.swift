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
    private let captureInsertionFingerprint: () -> String?
    private var requestInsertionFingerprint: String?
    private var conversationInsertionFingerprint: String?
    private var hasConversationInsertionTarget = false
    private var requestOOBEFeature: ManagedGatewayOOBEFeature?

    init(
        state: KeyboardState,
        flow: KeyboardFlowCoordinator,
        insertAnswer: @escaping (AIAnswer) -> Bool,
        performReturn: @escaping () -> Void,
        captureInsertionFingerprint: @escaping () -> String?
    ) {
        self.state = state
        self.flow = flow
        self.insertAnswer = insertAnswer
        self.performReturn = performReturn
        self.captureInsertionFingerprint = captureInsertionFingerprint
    }

    func beginNewPresentation() {
        endConversationIfNeeded()
        state.aiSession.enter()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        conversationInsertionFingerprint = nil
        hasConversationInsertionTarget = false
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
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        conversationInsertionFingerprint = nil
        hasConversationInsertionTarget = false
    }

    func toggleMicrophone() {
        switch state.aiSession.phase {
        case .listening:
            guard let utteranceID = state.aiSession.activeUtteranceID else { return }
            state.aiSession.beginRecognizing(utteranceID: utteranceID)
            flow.stopAIRecording()
        case .idle, .awaitingSend, .inserted, .sent, .failed:
            prepareConversationForRequest()
            guard let conversationID = state.aiSession.conversationID else { return }
            let oobeFeature = expectedOOBEFeature(.askAI)
            requestOOBEFeature = oobeFeature
            let disposition = flow.beginAIRecording(
                conversationID: conversationID,
                oobeFeature: oobeFeature
            )
            if case .rejected(let rejection) = disposition {
                state.aiSession.fail(message(for: rejection), utteranceID: nil)
            }
        case .inactive:
            prepareConversationForRequest()
            toggleMicrophone()
        case .preparing, .recognizing, .generating, .ready:
            break
        }
    }

    /// Tap a clipboard skill chip: same fail-closed material path as hint cards.
    func submitClipboardSkill(_ skill: AIClipboardSkill) {
        guard canAcceptIdleSubmit else { return }
        guard !skill.requiresShortcut
                || state.confirmedClipboardShortcutIDs.contains(skill.id) else {
            state.skillTipText = ExtL10n.string("keyboard.ai.skill.shortcutMissing")
            return
        }
        prepareConversationForRequest()
        let oobeFeature = oobeFeature(for: skill)
        let material: String?
        if let oobeFeature {
            // OOBE clipboard lessons are intentionally isolated from the
            // user's real clipboard history.
            material = oobeMaterial(for: oobeFeature)
        } else if state.oobePracticeSession != nil {
            material = nil
        } else {
            material = ClipboardHistoryStore.shared.newestAIHintEligibleEntry()?.text
        }
        if skill.kind == .export {
            state.pendingClipboardSkillID = skill.id
            state.pendingClipboardSkillSource = material
        } else {
            clearPendingExportSkill()
        }
        var instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: AIHintLocaleResolver.packLocale(),
            translationTargetLocaleId: state.translationTargetLocaleId
        )
        if skill.kind == .export {
            instruction += "\nPreserve the source language, addresses, names, and proper nouns."
        }
        AIAgentShortcutRun.trace("keyboard.submit skill=\(skill.id) kind=\(skill.kind)")
        if let material {
            AIAgentShortcutRun.traceBody("keyboard.clipboard", material)
        } else {
            AIAgentShortcutRun.trace("keyboard.clipboard missing")
        }
        let resolution = AIClipboardPrompt.resolve(
            instruction: instruction,
            material: material
        )
        if case .materialUnavailable = resolution {
            AIAgentShortcutRun.trace("keyboard.submit rejected clipboardUnavailable skill=\(skill.id)")
        }
        submitResolvedPrompt(
            resolution,
            taskKind: skill.managedGatewayTaskKind,
            oobeFeature: oobeFeature,
            thinkingEnabled: skill.thinkingEnabled
        )
    }

    /// Tap an idle hint card: resolve its material, skip the mic, ask the host.
    func submitHintCard(_ card: AIHintCard) {
        guard canAcceptIdleSubmit else { return }
        // The OOBE ask-AI lesson must use the explicit hold-to-talk path. Idle
        // cards can otherwise pull unrelated clipboard material into a request.
        guard state.oobePracticeSession == nil else { return }
        prepareConversationForRequest()
        let resolution = AIHintPool.resolvePrompt(
            for: card,
            clipboardText: ClipboardHistoryStore.shared.newestAIHintEligibleEntry()?.text
        )
        submitResolvedPrompt(
            resolution,
            taskKind: .aiQuestion,
            oobeFeature: nil
        )
    }

    private var canAcceptIdleSubmit: Bool {
        switch state.aiSession.phase {
        case .inactive, .idle, .awaitingSend, .inserted, .sent, .failed:
            return true
        case .preparing, .listening, .recognizing, .generating,
             .ready:
            return false
        }
    }

    private func submitResolvedPrompt(
        _ resolution: AIClipboardPrompt.Resolution,
        taskKind: ManagedGatewayTaskKind,
        oobeFeature: ManagedGatewayOOBEFeature? = nil,
        thinkingEnabled: Bool? = nil
    ) {
        guard case .ready(let prompt) = resolution else {
            // The clipboard window closed between rendering and this tap.
            clearPendingExportSkill()
            state.aiSession.fail(
                ExtL10n.string("keyboard.ai.error.clipboardUnavailable"),
                utteranceID: nil
            )
            return
        }
        guard let conversationID = state.aiSession.conversationID else {
            clearPendingExportSkill()
            return
        }
        requestOOBEFeature = oobeFeature
        let disposition = flow.submitAIQuestion(
            text: prompt,
            conversationID: conversationID,
            taskKind: taskKind,
            oobeFeature: oobeFeature,
            thinkingEnabled: thinkingEnabled
        )
        if case .rejected(let rejection) = disposition {
            clearPendingExportSkill()
            state.aiSession.fail(message(for: rejection), utteranceID: nil)
        }
    }

    func cancel() {
        guard state.aiSession.isBusy else { return }
        clearPendingExportSkill()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        flow.cancelAIRecording()
        state.aiSession.cancelCurrentWork()
    }

    func confirmPendingAnswer() {
        if state.aiSession.canInsert, let answer = state.aiSession.answer {
            guard insertAnswer(answer) else { return }
            markOOBECompletedAfterInsertion()
            state.aiSession.markAnswerInserted(
                offersSend: state.returnKeyRole.usesActionFill
            )
            conversationInsertionFingerprint = captureInsertionFingerprint()
            hasConversationInsertionTarget = true
        }
    }

    func discardPendingAnswer() {
        state.aiSession.discardReadyAnswer()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
    }

    func performCurrentFieldAction() {
        guard state.assistantActionAvailable else { return }
        if state.aiSession.canSend {
            state.aiSession.markAnswerSent()
        }
        // Let the host consume the inserted answer before issuing Return.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.performReturn()
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
        if isPendingExportSkill { return }
        state.aiSession.receivePartialAnswer(draft, utteranceID: utteranceID)
    }

    func receive(result: FlowResult) {
        guard result.resolvedUtteranceMode == .aiQuestion else {
            return
        }
        if isPendingExportSkill {
            guard result.aiConversationID == state.aiSession.conversationID else { return }
            finishExportSkill(answer: result.text ?? "")
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
        defer { requestInsertionFingerprint = nil }
        guard state.aiSession.canInsert,
              let expected = requestInsertionFingerprint,
              captureInsertionFingerprint() == expected,
              let answer = state.aiSession.answer,
              insertAnswer(answer) else {
            // Keep `.ready`: the unified UI presents an explicit Insert / Discard
            // fallback when the field or caret changed during generation.
            return
        }
        markOOBECompletedAfterInsertion()
        state.aiSession.markAnswerInserted(
            offersSend: state.returnKeyRole.usesActionFill
        )
        conversationInsertionFingerprint = captureInsertionFingerprint()
        hasConversationInsertionTarget = true
    }

    func fail(_ message: String, utteranceID: UUID?) {
        clearPendingExportSkill()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        state.aiSession.fail(message, utteranceID: utteranceID)
    }

    /// A global output-language change starts a clean conversation so retained
    /// turns cannot override the newly selected language policy.
    func resetConversationForConfigurationChange() {
        guard state.aiSession.isActive else { return }
        beginNewPresentation()
    }

    private func endConversationIfNeeded() {
        clearPendingExportSkill()
        guard let conversationID = state.aiSession.conversationID else { return }
        flow.endAIConversation(conversationID)
    }

    private func clearPendingExportSkill() {
        state.pendingClipboardSkillID = nil
        state.pendingClipboardSkillSource = nil
    }

    private func prepareConversationForRequest() {
        let currentFingerprint = captureInsertionFingerprint()
        if state.aiSession.isActive,
           hasConversationInsertionTarget,
           conversationInsertionFingerprint != currentFingerprint {
            beginNewPresentation()
        } else {
            enterIfNeeded()
        }
        conversationInsertionFingerprint = currentFingerprint
        hasConversationInsertionTarget = true
        requestInsertionFingerprint = currentFingerprint
    }

    private func oobeFeature(for skill: AIClipboardSkill) -> ManagedGatewayOOBEFeature? {
        switch skill.id {
        case AIClipboardSkillCatalog.replyID:
            return expectedOOBEFeature(.clipboardReply)
        case AIClipboardSkillCatalog.translateID:
            return expectedOOBEFeature(.clipboardTranslate)
        default:
            return nil
        }
    }

    private func expectedOOBEFeature(
        _ feature: ManagedGatewayOOBEFeature
    ) -> ManagedGatewayOOBEFeature? {
        guard state.oobePracticeSession?.expectedFeature == feature else { return nil }
        return feature
    }

    private func oobeMaterial(for feature: ManagedGatewayOOBEFeature?) -> String? {
        guard let feature,
              feature == .clipboardReply || feature == .clipboardTranslate,
              let session = state.oobePracticeSession else {
            return nil
        }
        return KeyboardSetupBridge.oobeClipboardMaterial(sessionID: session.sessionID)
    }

    private func markOOBECompletedAfterInsertion() {
        guard let feature = requestOOBEFeature,
              let session = state.oobePracticeSession else {
            return
        }
        _ = KeyboardSetupBridge.markOOBEPracticeCompleted(
            sessionID: session.sessionID,
            feature: feature
        )
    }

    private var isPendingExportSkill: Bool {
        guard let id = state.pendingClipboardSkillID else { return false }
        return resolvedSkill(id: id)?.kind == .export
    }

    private func resolvedSkill(id: String) -> AIClipboardSkill? {
        state.clipboardSkillCatalog.first { $0.id == id }
    }

    /// Parse an export skill. Empty → in-keyboard tip, stay in the host app.
    /// Lines → hand off to the host (Shortcut, Maps, or Didi).
    private func finishExportSkill(answer: String) {
        let source = state.pendingClipboardSkillSource
            ?? ClipboardHistoryStore.shared.newestAIHintEligibleEntry()?.text
        let skillID = state.pendingClipboardSkillID
        let items: [String]
        let emptyTipKey: String
        switch skillID {
        case AIClipboardSkillCatalog.extractEventsID:
            items = AIEventExtraction.lines(from: answer, sourceClipboard: source)
            emptyTipKey = "keyboard.ai.skill.noEvents"
        case AIClipboardSkillCatalog.extractTodosID:
            items = AITodoExtraction.items(from: answer, sourceClipboard: source)
            emptyTipKey = "keyboard.ai.skill.noTodos"
        case AIClipboardSkillCatalog.navigateID:
            items = AIAddressExtraction.lines(from: answer, sourceClipboard: source)
            emptyTipKey = "keyboard.ai.skill.noAddress"
        case AIClipboardSkillCatalog.saveToNotesID:
            items = AINoteExport.items(
                from: answer,
                sourceClipboard: source,
                locale: AIHintLocaleResolver.packLocale()
            )
            emptyTipKey = "keyboard.ai.skill.noNote"
        default:
            items = AIGenericSkillExport.items(from: answer)
            emptyTipKey = "keyboard.ai.skill.noExportItems"
        }
        AIAgentShortcutRun.traceBody("keyboard.llmRaw", answer)
        AIAgentShortcutRun.trace(
            "keyboard.parse items=\(items.count) clipboardChars=\(source?.count ?? 0)"
        )
        #if DEBUG
        if !items.isEmpty {
            AIAgentShortcutRun.traceBody("keyboard.parsedTitles", items.joined(separator: "\n"))
        }
        #endif
        clearPendingExportSkill()
        if state.aiSession.isBusy {
            state.aiSession.cancelCurrentWork()
        }
        if state.aiSession.isActive {
            state.aiSession.resetConversationPreservingAnswer()
        }
        guard !items.isEmpty else {
            AIAgentShortcutRun.trace("keyboard.parse empty — skip Shortcuts")
            state.skillTipText = ExtL10n.string(emptyTipKey)
            return
        }
        guard let skillID, let skill = resolvedSkill(id: skillID) else {
            AIAgentShortcutRun.trace("keyboard.parse missingSkill")
            state.skillTipText = ExtL10n.string("keyboard.ai.skill.shortcutMissing")
            return
        }
        if skill.requiresShortcut, skill.shortcutName == nil {
            AIAgentShortcutRun.trace("keyboard.parse missingShortcut skill=\(skillID)")
            state.skillTipText = ExtL10n.string("keyboard.ai.skill.shortcutMissing")
            return
        }
        AIAgentShortcutRun.trace("keyboard.handoffToHost skill=\(skillID) items=\(items.count)")
        let tipKey: String
        switch skillID {
        case AIClipboardSkillCatalog.navigateID:
            tipKey = "keyboard.ai.skill.openingMaps"
        default:
            tipKey = "keyboard.ai.skill.runningShortcut"
        }
        state.skillTipText = ExtL10n.string(tipKey)
        state.runClipboardExportSkill(skillID, items)
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
