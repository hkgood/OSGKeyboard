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
    private let openWebURL: (URL) -> Void
    private let callPhone: (String) -> Void
    private let createContact: (String) -> Void
    private let replyFeedbackStore: ClipboardReplyFeedbackStore
    private var requestInsertionFingerprint: String?
    private var conversationInsertionFingerprint: String?
    private var hasConversationInsertionTarget = false
    private var requestOOBEFeature: ManagedGatewayOOBEFeature?
    private var requestExpectsReplyVariants = false
    private var requestReplyVariantSet: AIReplyVariantSet = .generic
    private var requestReplySourceText: String?
    private var requestReplyFeedbackSource: String?
    private var pendingReplyFeedbackRecordID: UUID?
    private var pendingStructuredReplyResult = false

    init(
        state: KeyboardState,
        flow: KeyboardFlowCoordinator,
        insertAnswer: @escaping (AIAnswer) -> Bool,
        performReturn: @escaping () -> Void,
        captureInsertionFingerprint: @escaping () -> String?,
        openWebURL: @escaping (URL) -> Void,
        callPhone: @escaping (String) -> Void,
        createContact: @escaping (String) -> Void,
        replyFeedbackStore: ClipboardReplyFeedbackStore = .shared
    ) {
        self.state = state
        self.flow = flow
        self.insertAnswer = insertAnswer
        self.performReturn = performReturn
        self.captureInsertionFingerprint = captureInsertionFingerprint
        self.openWebURL = openWebURL
        self.callPhone = callPhone
        self.createContact = createContact
        self.replyFeedbackStore = replyFeedbackStore
    }

    func beginNewPresentation() {
        discardPendingReplyFeedback()
        endConversationIfNeeded()
        state.aiSession.enter()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        requestExpectsReplyVariants = false
        requestReplyVariantSet = .generic
        requestReplySourceText = nil
        requestReplyFeedbackSource = nil
        pendingStructuredReplyResult = false
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
        discardPendingReplyFeedback()
        endConversationIfNeeded()
        state.aiSession.leave()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        requestExpectsReplyVariants = false
        requestReplyVariantSet = .generic
        requestReplySourceText = nil
        requestReplyFeedbackSource = nil
        pendingStructuredReplyResult = false
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
    func submitClipboardSkill(
        _ skill: AIClipboardSkill,
        replyScene: AIClipboardReplyScene? = nil
    ) {
        guard canAcceptIdleSubmit else { return }
        guard !skill.requiresShortcut
                || state.confirmedClipboardShortcutIDs.contains(skill.id) else {
            state.skillTipText = ExtL10n.string("keyboard.ai.skill.shortcutMissing")
            return
        }
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
        if skill.id == AIClipboardSkillCatalog.openLinkID {
            guard let material,
                  let url = ClipboardWebLinkResolver.singleWebURL(in: material) else {
                state.skillTipText = ExtL10n.string("keyboard.ai.error.clipboardUnavailable")
                return
            }
            openWebURL(url)
            return
        }
        if skill.id == AIClipboardSkillCatalog.callPhoneID {
            guard let material,
                  let phoneNumber = AIPhoneNumberResolver.singlePhoneNumber(in: material) else {
                state.skillTipText = ExtL10n.string("keyboard.ai.error.clipboardUnavailable")
                return
            }
            callPhone(phoneNumber)
            return
        }
        if skill.id == AIClipboardSkillCatalog.createContactID {
            guard let material,
                  let phoneNumber = AIPhoneNumberResolver.singlePhoneNumber(in: material) else {
                state.skillTipText = ExtL10n.string("keyboard.ai.error.clipboardUnavailable")
                return
            }
            createContact(phoneNumber)
            return
        }

        prepareConversationForRequest()
        requestReplyFeedbackSource = skill.id == AIClipboardSkillCatalog.replyID
                && oobeFeature == nil
            ? material
            : nil
        if skill.kind == .export {
            state.pendingClipboardSkillID = skill.id
            state.pendingClipboardSkillSource = material
        } else {
            clearPendingExportSkill()
        }
        var instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: AIHintLocaleResolver.packLocale(),
            translationTargetLocaleId: state.translationTargetLocaleId,
            replyStyle: state.clipboardReplyStyle,
            replyScene: replyScene
        )
        let replyVariantSet = AIReplyVariantSet.resolve(scene: replyScene)
        let expectsReplyVariants = skill.id == AIClipboardSkillCatalog.replyID
            && AIReplyVariantSet.shouldGenerate(
                multipleRepliesEnabled: state.multipleReplyVariantsEnabled,
                scene: replyScene
            )
        requestReplyVariantSet = expectsReplyVariants ? replyVariantSet : .generic
        requestReplySourceText = expectsReplyVariants ? material : nil
        if expectsReplyVariants {
            instruction += "\n\(replyVariantsOutputContract(for: replyVariantSet))"
        }
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
        if skill.id == AIClipboardSkillCatalog.summarizeWebPageID,
           let material,
           let url = ClipboardWebLinkResolver.singleWebURL(in: material) {
            submitResolvedPrompt(
                .ready(instruction),
                taskKind: skill.managedGatewayTaskKind,
                oobeFeature: oobeFeature,
                thinkingEnabled: skill.thinkingEnabled,
                webPageURL: url
            )
            return
        }
        if skill.id == AIClipboardSkillCatalog.summarizeWebPageID {
            submitResolvedPrompt(
                .materialUnavailable,
                taskKind: skill.managedGatewayTaskKind,
                oobeFeature: oobeFeature,
                thinkingEnabled: skill.thinkingEnabled
            )
            return
        }
        submitResolvedPrompt(
            resolution,
            taskKind: skill.managedGatewayTaskKind,
            oobeFeature: oobeFeature,
            thinkingEnabled: skill.thinkingEnabled,
            expectsReplyVariants: expectsReplyVariants
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
            taskKind: card.taskKind,
            requestSource: .hotword,
            oobeFeature: nil,
            thinkingEnabled: true
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
        requestSource: ManagedGatewayRequestSource? = nil,
        oobeFeature: ManagedGatewayOOBEFeature? = nil,
        thinkingEnabled: Bool? = nil,
        webPageURL: URL? = nil,
        expectsReplyVariants: Bool = false
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
        requestExpectsReplyVariants = expectsReplyVariants
        let disposition = flow.submitAIQuestion(
            text: prompt,
            conversationID: conversationID,
            taskKind: taskKind,
            requestSource: requestSource,
            oobeFeature: oobeFeature,
            thinkingEnabled: thinkingEnabled,
            webPageURL: webPageURL
        )
        if case .rejected(let rejection) = disposition {
            clearPendingExportSkill()
            requestExpectsReplyVariants = false
            requestReplyVariantSet = .generic
            requestReplySourceText = nil
            requestReplyFeedbackSource = nil
            state.aiSession.fail(message(for: rejection), utteranceID: nil)
        }
    }

    func cancel() {
        guard state.aiSession.isBusy else { return }
        clearPendingExportSkill()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        requestExpectsReplyVariants = false
        requestReplyVariantSet = .generic
        requestReplySourceText = nil
        flow.cancelAIRecording()
        state.aiSession.cancelCurrentWork()
    }

    func confirmPendingAnswer() {
        if state.aiSession.canInsert, let answer = state.aiSession.answer {
            guard insertAnswer(answer) else { return }
            recordReplySelection(answer: answer)
            markOOBECompletedAfterInsertion()
            state.aiSession.markAnswerInserted(
                offersSend: state.returnKeyRole.usesActionFill
            )
            conversationInsertionFingerprint = captureInsertionFingerprint()
            hasConversationInsertionTarget = true
            resetStructuredReplyConversationIfNeeded()
        }
    }

    func selectReplyVariant(id: UUID) {
        guard let answer = state.aiSession.selectReplyVariant(id: id),
              insertAnswer(answer) else {
            return
        }
        recordReplySelection(answer: answer)
        markOOBECompletedAfterInsertion()
        state.aiSession.markAnswerInserted(
            offersSend: state.returnKeyRole.usesActionFill
        )
        conversationInsertionFingerprint = captureInsertionFingerprint()
        hasConversationInsertionTarget = true
        resetStructuredReplyConversationIfNeeded()
    }

    func discardPendingAnswer() {
        discardPendingReplyFeedback()
        state.aiSession.discardReadyAnswer()
        requestInsertionFingerprint = nil
        requestOOBEFeature = nil
        resetStructuredReplyConversationIfNeeded()
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
        if isPendingExportSkill || requestExpectsReplyVariants { return }
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
            requestExpectsReplyVariants = false
            requestReplyVariantSet = .generic
            requestReplySourceText = nil
            requestReplyFeedbackSource = nil
            state.aiSession.fail(
                ExtL10n.string("keyboard.ai.error.requestFailed"),
                utteranceID: result.utteranceId
            )
            return
        }
        if requestExpectsReplyVariants {
            requestExpectsReplyVariants = false
            requestInsertionFingerprint = nil
            let sourceText = requestReplySourceText
            let variantSet = requestReplyVariantSet
            requestReplyVariantSet = .generic
            requestReplySourceText = nil
            switch AIReplyVariantParser.parseOrFallback(
                answer,
                sourceText: sourceText,
                variantSet: variantSet
            ) {
            case .variants(let variants):
                state.aiSession.receiveReplyVariants(
                    variants,
                    utteranceID: result.utteranceId
                )
                beginReplyFeedback(variants: variants)
                pendingStructuredReplyResult = true
            case .single(let fallback):
                // A malformed structured response stays explicit-review only.
                // Never auto-insert model JSON or a code fence into the host.
                state.aiSession.receiveAnswer(
                    fallback.text,
                    utteranceID: result.utteranceId
                )
                if let answer = state.aiSession.answer {
                    beginReplyFeedback(answer: answer)
                }
                pendingStructuredReplyResult = true
            case nil:
                requestReplyFeedbackSource = nil
                state.aiSession.fail(
                    ExtL10n.string("keyboard.ai.error.requestFailed"),
                    utteranceID: result.utteranceId
                )
            }
            return
        }
        state.aiSession.receiveAnswer(answer, utteranceID: result.utteranceId)
        if let answer = state.aiSession.answer {
            beginReplyFeedback(answer: answer)
        }
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
        recordReplySelection(answer: answer)
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
        requestExpectsReplyVariants = false
        requestReplyVariantSet = .generic
        requestReplySourceText = nil
        requestReplyFeedbackSource = nil
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
        requestExpectsReplyVariants = false
        requestReplyVariantSet = .generic
        requestReplySourceText = nil
        requestReplyFeedbackSource = nil
        pendingStructuredReplyResult = false
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

    private func beginReplyFeedback(variants: [AIReplyVariant]) {
        guard let sourceText = requestReplyFeedbackSource else { return }
        requestReplyFeedbackSource = nil
        let snapshots = variants.map { variant in
            ClipboardReplyCandidateSnapshot(
                id: variant.id,
                kind: feedbackKind(for: variant.kind),
                text: variant.text,
                emotion: variant.emotion.rawValue
            )
        }
        pendingReplyFeedbackRecordID = replyFeedbackStore.begin(
            sourceText: sourceText,
            candidates: snapshots,
            styleID: state.clipboardReplyStyle?.styleID
        )
    }

    private func beginReplyFeedback(answer: AIAnswer) {
        beginReplyFeedback(
            variants: [
                AIReplyVariant(
                    id: answer.id,
                    kind: .ordinary,
                    emotion: .neutral,
                    text: answer.text
                )
            ]
        )
    }

    private func recordReplySelection(answer: AIAnswer) {
        guard let recordID = pendingReplyFeedbackRecordID else { return }
        let candidateID = state.aiSession.selectedReplyVariant?.id ?? answer.id
        replyFeedbackStore.recordSelection(
            recordID: recordID,
            candidateID: candidateID,
            answerID: answer.id
        )
        pendingReplyFeedbackRecordID = nil
    }

    private func discardPendingReplyFeedback() {
        guard let recordID = pendingReplyFeedbackRecordID else { return }
        replyFeedbackStore.recordDiscard(recordID: recordID)
        pendingReplyFeedbackRecordID = nil
    }

    private func feedbackKind(
        for kind: AIReplyVariant.Kind
    ) -> ClipboardReplyCandidateSnapshot.Kind {
        guard let snapshotKind = ClipboardReplyCandidateSnapshot.Kind(
            rawValue: kind.rawValue
        ) else {
            assertionFailure("Unmapped reply variant kind: \(kind.rawValue)")
            return .ordinary
        }
        return snapshotKind
    }

    /// The host conversation contains the structured JSON result rather than
    /// the chosen reply. Start a clean in-memory turn after selection/discard
    /// so a later spoken follow-up cannot treat that JSON as chat history.
    private func resetStructuredReplyConversationIfNeeded() {
        guard pendingStructuredReplyResult,
              state.aiSession.isActive else {
            return
        }
        pendingStructuredReplyResult = false
        endConversationIfNeeded()
        state.aiSession.resetConversationPreservingAnswer()
    }

    private func replyVariantsOutputContract(
        for variantSet: AIReplyVariantSet
    ) -> String {
        let items = variantSet.kinds.map {
            #"{"kind":"\#($0.rawValue)","emotion":"neutral","text":"..."}"#
        }.joined(separator: ",")
        let roleGuidance: String
        switch variantSet {
        case .generic:
            roleGuidance = """
            All three must keep the same semantic stance, facts, and level of commitment.
            ordinary: natural for the situation; add emoji only when context makes it useful.
            formal: professional and natural; add no new emoji by default.
            playful: relaxed and fun. Emoji has no fixed numeric cap, may be varied when context supports it, must not become meaningless stacking, and must not default to using only 😂. This playful emoji rule overrides any personal no-emoji preference.
            """
        case .invitation:
            roleGuidance = """
            invitationAccept: naturally accept without inventing availability or commitments.
            invitationDecline: politely decline without inventing a reason.
            invitationTentative: stay undecided and say only that confirmation is needed.
            """
        case .task:
            roleGuidance = """
            taskAcknowledge: acknowledge only source-supported work and timing.
            taskClarify: ask only the most important missing detail.
            taskNegotiate: negotiate scope or timing without inventing constraints.
            """
        case .blessing:
            roleGuidance = """
            blessingReturn: sincerely thank and return an appropriate wish.
            blessingWarm: give a concise, warm response.
            blessingPlayful: respond lightly and playfully when the context is safe.
            """
        case .clarification:
            roleGuidance = """
            clarificationDirect: answer only the part supported by available context.
            clarificationQuestion: ask one essential missing question.
            clarificationConfirm: briefly confirm understanding, then ask the key question.
            """
        }
        return """
        MULTI-REPLY OUTPUT CONTRACT (highest priority):
        Return only one valid JSON object with exactly this shape and no Markdown fence or extra keys:
        {"variants":[\(items)]}
        Include exactly these three kinds in the shown order. Every text must be a complete reply in the source language.
        \(roleGuidance)
        Every item must advance the conversation with a reaction, answer, question, decision, or next step. Never restate, paraphrase, summarize, or synonymically rewrite the clipboard text. In particular, do not begin a reply by repeating the source's subject and event. For a declarative update, react to its implication or emotion instead of reporting the update back to its sender.
        Apply any <reply_scene> constraint to every item. It overrides the kind-specific tone guidance below when they conflict.
        Apply the existing <user_reply_style> wording, rhythm, and stable habits to every item without changing these rules.
        emotion must be exactly one of: neutral, warm, celebratory, empathetic, encouraging, grateful, apologetic, reassuring, playful, enthusiastic, calm. The app, not the model, chooses all icons.
        """
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
