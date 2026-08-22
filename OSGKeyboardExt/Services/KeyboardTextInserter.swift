// KeyboardTextInserter.swift
// OSGKeyboard · Keyboard Extension
//
// Inserts Flow transcripts from the host app and surfaces polish warnings
// without re-running LLM polish in the extension. Also tracks the last
// voice insertion so the undo button can roll it back safely.

import OSGKeyboardShared
import UIKit

@MainActor
final class KeyboardTextInserter {
    /// Hosts truncate `documentContextBeforeInput` (often to the current
    /// paragraph), so a long insertion can only ever be matched by its tail.
    private static let caretVerificationLimit = 80

    private let state: KeyboardState
    private let insertText: (String, KeyboardTextInsertionSource) -> Void
    private let deleteBackward: () -> Void
    private let contextBeforeInput: () -> String?
    private let fieldContextProvider: () -> FlowFieldContext?
    private let selectedText: () -> String?
    private let scheduleAutoClearError: () -> Void
    private unowned let editHintScheduler: EditHintScheduler

    /// Exact string last inserted through this inserter — dictation, AI answer,
    /// edit result or clipboard paste (including any word-boundary separator).
    /// Cleared after a successful undo or when the caret no longer sits after
    /// that text.
    private var lastInsertedText: String?
    /// Text captured when the last insertion was undone, so redo can
    /// re-apply it. Cleared by any new insertion or external edit.
    private var redoText: String?
    private var redoContextBefore: String?
    private let extensionInstanceID = UUID()
    private var lastEditUndo: PendingTextEditTransaction?
    /// Suppresses availability refresh while we walk `deleteBackward`
    /// for undo, so intermediate contexts don't flicker the button.
    private var isUndoing = false
    private var successPulseTask: Task<Void, Never>?

    init(
        state: KeyboardState,
        insertText: @escaping (String, KeyboardTextInsertionSource) -> Void,
        deleteBackward: @escaping () -> Void,
        contextBeforeInput: @escaping () -> String?,
        fieldContextProvider: @escaping () -> FlowFieldContext?,
        selectedText: @escaping () -> String?,
        scheduleAutoClearError: @escaping () -> Void,
        editHintScheduler: EditHintScheduler
    ) {
        self.state = state
        self.insertText = insertText
        self.deleteBackward = deleteBackward
        self.contextBeforeInput = contextBeforeInput
        self.fieldContextProvider = fieldContextProvider
        self.selectedText = selectedText
        self.scheduleAutoClearError = scheduleAutoClearError
        self.editHintScheduler = editHintScheduler
    }

    func handleFlowTranscript(
        _ delivery: TranscriptionDelivery,
        replacePrevious: String? = nil
    ) {
        let trimmed = delivery.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.phase = .idle
            state.level = 0
            return
        }

        if let previous = replacePrevious?.trimmingCharacters(in: .whitespacesAndNewlines),
           !previous.isEmpty,
           let preceding = contextBeforeInput(),
           preceding.hasSuffix(previous) {
            for _ in 0..<previous.count {
                deleteBackward()
            }
        }

        // Host app already polished when configured; keyboard only inserts.
        // Word-boundary hygiene: dictating "world" with the cursor right
        // after "Hello" must yield "Hello world", not "Helloworld".
        let separator = DictationTextComposer.insertionSeparator(
            previousContext: contextBeforeInput(),
            insertion: trimmed
        )
        let inserted = separator + trimmed
        insertText(inserted, .voiceTranscription)
        KeyboardSetupBridge.markVoiceInsertion()
        if delivery.polishWarning == nil,
           let practice = state.oobePracticeSession,
           practice.expectedFeature == .voiceInput {
            _ = KeyboardSetupBridge.markOOBEPracticeCompleted(
                sessionID: practice.sessionID,
                feature: .voiceInput
            )
        }
        state.noteUserDidInputText()
        recordLastInsertion(
            inserted,
            displayText: trimmed,
            historyEntryID: delivery.historyEntryID,
            historyEntryRevision: delivery.historyEntryRevision,
            pendingHistoryMutationID: nil
        )
        state.lastTranscript = ""
        state.level = 0
        if let warning = delivery.polishWarning {
            state.phase = .error(.polishDegraded(warning), message: warning)
            scheduleAutoClearError()
        } else {
            state.phase = .idle
        }
        OSGLog.keyboardExt.info("flow insert length=\(trimmed.count, privacy: .public)")
    }

    /// Insert one explicitly confirmed AI answer and enqueue history/statistics
    /// only after the field mutation has been issued.
    @discardableResult
    func insertAIAnswer(_ answer: AIAnswer) -> Bool {
        let trimmed = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let separator = DictationTextComposer.insertionSeparator(
            previousContext: contextBeforeInput(),
            insertion: trimmed
        )
        let inserted = separator + trimmed
        insertText(inserted, .aiGenerated)
        state.noteUserDidInputText()

        let mutation = HistoryMutation(
            action: .append,
            entryID: answer.id,
            text: trimmed,
            engineMode: state.engineMode,
            source: .ai,
            usageCategory: .ai
        )
        HistoryMutationOutbox.enqueue(mutation)
        recordLastInsertion(
            inserted,
            displayText: trimmed,
            historyEntryID: answer.id,
            historyEntryRevision: 0,
            pendingHistoryMutationID: mutation.id
        )
        state.lastTranscript = ""
        state.level = 0
        OSGLog.keyboardExt.info("AI answer insert length=\(trimmed.count, privacy: .public)")
        return true
    }

    /// Insert clipboard text verbatim and make it undoable. Pasted text is not
    /// a dictation result: it never becomes an editable "last input" reference
    /// and never reaches the history outbox, so it only takes the undo record.
    func insertPasteboardText(_ text: String) {
        guard !text.isEmpty else { return }
        // Verbatim on purpose — paste must reproduce exactly what was copied,
        // unlike dictation which needs word-boundary hygiene.
        insertText(text, .pasteboard)
        recordUndoableInsertion(text)
        // The paste pushed any previous input away from the caret, so the
        // "editable last input" hint no longer applies.
        clearEditHintIfPositive()
        state.editAvailable = false
        OSGLog.keyboardExt.info("clipboard insert length=\(text.count, privacy: .public)")
    }

    /// Roll back the last insertion when it is still at the caret.
    func undoLastInsertion() {
        if undoLastEditIfPossible() {
            return
        }
        guard let text = lastInsertedText, !text.isEmpty else { return }
        guard caretSitsAfter(text) else {
            clearLastInsertion()
            return
        }

        isUndoing = true
        defer { isUndoing = false }

        // `UITextDocumentProxy` has no ranged delete, so the whole insertion is
        // walked back one grapheme at a time. Staying synchronous keeps it in a
        // single run-loop turn, which the host coalesces into one visual update.
        for _ in 0..<text.count {
            deleteBackward()
        }
        // Stash the exact inserted string (incl. separator) for redo before
        // dropping the live undo record.
        redoText = text
        redoContextBefore = contextBeforeInput()
        lastInsertedText = nil
        state.undoAvailable = false
        state.editAvailable = false
        EditableInputReferenceStore.clear()
        OSGLog.keyboardExt.info("undo length=\(text.count, privacy: .public)")
    }

    /// Re-apply the last undone insertion when it is still absent from the
    /// caret (i.e. the undo was not overwritten by an external edit).
    func redoLastInsertion() {
        guard let text = redoText, !text.isEmpty,
              contextBeforeInput() == redoContextBefore else {
            redoText = nil
            redoContextBefore = nil
            state.redoAvailable = false
            return
        }
        guard !caretSitsAfter(text) else {
            redoText = nil
            state.redoAvailable = false
            return
        }
        insertText(text, .redo)
        recordUndoableInsertion(text)
        OSGLog.keyboardExt.info("redo length=\(text.count, privacy: .public)")
    }

    /// Copy the host field's current selection to the pasteboard. Needs Full
    /// Access for `selectedText` on some hosts; silently no-ops otherwise.
    func copySelection() {
        guard let text = selectedText(), !text.isEmpty else { return }
        UIPasteboard.general.string = text
        OSGLog.keyboardExt.info("copy length=\(text.count, privacy: .public)")
    }

    /// Copy the host field's current selection, then delete it.
    func cutSelection() {
        guard let text = selectedText(), !text.isEmpty else { return }
        UIPasteboard.general.string = text
        // `deleteBackward` removes the active selection in one operation.
        deleteBackward()
        OSGLog.keyboardExt.info("cut length=\(text.count, privacy: .public)")
    }

    /// Re-evaluate undo / redo / copy / cut availability. Call from
    /// `textDidChange` / `selectionDidChange`.
    func refreshEditingAvailability() {
        // Undo: only re-check when not mid-undo (avoids flicker while we walk
        // `deleteBackward`); the undo method manages availability itself.
        if !isUndoing {
            if let text = lastInsertedText, !text.isEmpty {
                let available = caretSitsAfter(text)
                if !available {
                    // Caret moved or the user edited the insertion — drop it.
                    lastInsertedText = nil
                    state.undoAvailable = false
                } else if !state.undoAvailable {
                    state.undoAvailable = true
                }
            } else if state.undoAvailable {
                state.undoAvailable = false
            }
        }

        // Redo: a stashed insertion that hasn't been overwritten by an edit.
        if redoText != nil, contextBeforeInput() != redoContextBefore {
            redoText = nil
            redoContextBefore = nil
        }
        let redo = redoText != nil && !(redoText?.isEmpty ?? true)
        if state.redoAvailable != redo {
            state.redoAvailable = redo
        }

        // Copy / cut: a non-empty selection exists in the host field.
        let hasSelection = (selectedText()?.isEmpty == false)
        if state.copyAvailable != hasSelection {
            state.copyAvailable = hasSelection
        }
        if state.cutAvailable != hasSelection {
            state.cutAvailable = hasSelection
        }
        let editAvailable = editableReference() != nil
        if state.editAvailable != editAvailable {
            state.editAvailable = editAvailable
        }
    }

    func editableReference() -> EditableInputReference? {
        guard var reference = EditableInputReferenceStore.load() else {
            return nil
        }
        if let mutationID = reference.pendingHistoryMutationID,
           let receipt = HistoryMutationReceiptStore.receipt(for: mutationID) {
            reference = EditableInputReference(
                targetID: reference.targetID,
                historyEntryID: receipt.entryID,
                historyEntryRevision: receipt.revision,
                displayText: reference.displayText,
                insertedText: reference.insertedText,
                postInsertionFingerprint: reference.postInsertionFingerprint,
                extensionInstanceID: reference.extensionInstanceID,
                observedDocumentRevision: reference.observedDocumentRevision,
                createdAt: reference.createdAt
            )
            EditableInputReferenceStore.save(reference)
        }
        guard reference.isWithinLengthBudget,
              let preceding = contextBeforeInput(),
              preceding.hasSuffix(reference.insertedText) else {
            return nil
        }
        // The current extension instance owns an exact in-memory insertion
        // record. Prefer it before the cross-process field fingerprint:
        // UITextDocumentProxy can publish its updated surrounding context one
        // callback after `insertText`, which otherwise makes a freshly shown
        // Edit button disappear or reject its first tap.
        if reference.matchesLiveInsertion(
            extensionInstanceID: extensionInstanceID,
            lastInsertedText: lastInsertedText,
            contextBeforeInput: preceding
        ) {
            return reference
        }
        guard reference.postInsertionFingerprint == nil
                || reference.postInsertionFingerprint
                    == fieldContextProvider()?.deliveryFingerprint else {
            return nil
        }
        // Rebuilt extension instances have no trusted in-memory insertion
        // record, so they continue to require the complete field fingerprint.
        return reference.isFullyVerified(
            contextBeforeInput: preceding,
            fieldFingerprint: fieldContextProvider()?.deliveryFingerprint
        ) ? reference : nil
    }

    @discardableResult
    func applyEdit(_ review: EditReview, append: Bool) -> Bool {
        let source = review.source.reference
        let result = review.resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return false }

        let mode: PendingTextEditTransaction.DeliveryMode = append ? .append : .replace
        if append {
            guard let context = fieldContextProvider(),
                  !context.isSecureEntry,
                  context.isContextAvailable else {
                return false
            }
        }
        if !append {
            guard editableReference()?.targetID == source.targetID else { return false }
        }

        let historyEntryID = append
            ? UUID()
            : (source.historyEntryID ?? UUID())
        let historyAction: HistoryMutation.Action = append || source.historyEntryID == nil
            ? .append
            : .update
        let mutation = HistoryMutation(
            action: historyAction,
            entryID: historyEntryID,
            expectedRevision: historyAction == .update
                ? source.historyEntryRevision
                : nil,
            text: result
        )
        var transaction = PendingTextEditTransaction(
            deliveryMode: mode,
            beforeText: source.insertedText,
            afterText: result,
            expectedFieldFingerprint: fieldContextProvider()?.deliveryFingerprint,
            historyMutation: mutation
        )
        PendingTextEditTransactionStore.save(transaction)

        if !append {
            for _ in source.insertedText {
                deleteBackward()
            }
        }
        let separator = DictationTextComposer.insertionSeparator(
            previousContext: contextBeforeInput(),
            insertion: result
        )
        let inserted = separator + result
        transaction.appliedInsertedText = inserted
        PendingTextEditTransactionStore.save(transaction)
        insertText(inserted, .editGenerated)
        let verificationSuffix = String(inserted.suffix(80))
        guard contextBeforeInput()?.hasSuffix(verificationSuffix) == true else {
            // Never blindly delete after a partial/opaque host insertion. The
            // durable transaction lets a later presentation reconcile safely.
            return false
        }

        transaction.phase = .fieldApplied
        PendingTextEditTransactionStore.save(transaction)
        HistoryMutationOutbox.enqueue(mutation)
        transaction.phase = .committed
        PendingTextEditTransactionStore.save(transaction)
        recordLastInsertion(
            inserted,
            displayText: result,
            historyEntryID: historyEntryID,
            historyEntryRevision: historyAction == .update
                ? (source.historyEntryRevision ?? 0) + 1
                : 0,
            pendingHistoryMutationID: mutation.id
        )
        // Set after recording: the shared bookkeeping drops any stale
        // transaction, and this one must survive as the undo target.
        lastEditUndo = transaction
        PendingTextEditTransactionStore.clear()
        return true
    }

    @discardableResult
    func recoverPendingEditTransactionIfNeeded() -> Bool {
        guard let transaction = PendingTextEditTransactionStore.load(),
              let preceding = contextBeforeInput() else {
            return false
        }
        let currentFingerprint = fieldContextProvider()?.deliveryFingerprint
        let appliedText = transaction.appliedInsertedText ?? transaction.afterText
        if transaction.phase != .prepared,
           preceding.hasSuffix(appliedText) {
            HistoryMutationOutbox.enqueue(transaction.historyMutation)
            PendingTextEditTransactionStore.clear()
            return true
        }
        if transaction.phase == .prepared,
           currentFingerprint != transaction.expectedFieldFingerprint,
           preceding.hasSuffix(appliedText) {
            HistoryMutationOutbox.enqueue(transaction.historyMutation)
            PendingTextEditTransactionStore.clear()
            return true
        }
        if transaction.deliveryMode == .replace,
           preceding.hasSuffix(transaction.beforeText) {
            PendingTextEditTransactionStore.clear()
            return false
        }
        return false
    }

    private func undoLastEditIfPossible() -> Bool {
        guard let transaction = lastEditUndo else {
            return false
        }
        let insertedAfter = lastInsertedText ?? transaction.afterText
        guard caretSitsAfter(insertedAfter) else {
            lastEditUndo = nil
            return false
        }
        for _ in insertedAfter {
            deleteBackward()
        }

        switch transaction.deliveryMode {
        case .replace:
            insertText(transaction.beforeText, .editGenerated)
            let restore = HistoryMutation(
                action: transaction.historyMutation.action == .append ? .delete : .restore,
                entryID: transaction.historyMutation.entryID,
                expectedRevision: transaction.historyMutation.expectedRevision.map { $0 + 1 },
                text: transaction.beforeText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            HistoryMutationOutbox.enqueue(restore)
            recordLastInsertion(
                transaction.beforeText,
                displayText: transaction.beforeText
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                historyEntryID: transaction.historyMutation.action == .append
                    ? nil
                    : transaction.historyMutation.entryID,
                historyEntryRevision: transaction.historyMutation.expectedRevision.map { $0 + 2 },
                pendingHistoryMutationID: restore.id
            )
        case .append:
            HistoryMutationOutbox.enqueue(
                HistoryMutation(
                    action: .delete,
                    entryID: transaction.historyMutation.entryID
                )
            )
            clearLastInsertion()
        }
        lastEditUndo = nil
        return true
    }

    /// Is the caret still sitting right after `text`?
    ///
    /// The comparison is limited to the tail of the insertion's last line: a
    /// truncated host context can never contain the earlier part, and text
    /// before a line break is usually stripped from `documentContextBeforeInput`.
    private func caretSitsAfter(_ text: String) -> Bool {
        guard let preceding = contextBeforeInput() else { return false }
        let lastLine: String
        if let breakRange = text.rangeOfCharacter(from: .newlines, options: .backwards) {
            lastLine = String(text[breakRange.upperBound...])
        } else {
            lastLine = text
        }
        let expected = String(lastLine.suffix(Self.caretVerificationLimit))
        // The insertion ended on a line break, so nothing measurable is left
        // before the caret — an empty context is the expected state.
        guard !expected.isEmpty else { return preceding.isEmpty }
        return preceding.hasSuffix(expected)
    }

    /// Undo bookkeeping shared by every insertion path. Callers that also own
    /// history / editable-reference state layer `recordLastInsertion` on top.
    private func recordUndoableInsertion(_ text: String) {
        lastInsertedText = text
        redoText = nil
        redoContextBefore = nil
        // A newer insertion supersedes any edit transaction: undo must roll back
        // this text, not re-apply the original text of an older edit.
        lastEditUndo = nil
        state.undoAvailable = true
    }

    private func recordLastInsertion(
        _ text: String,
        displayText: String,
        historyEntryID: UUID?,
        historyEntryRevision: Int64?,
        pendingHistoryMutationID: UUID?
    ) {
        recordUndoableInsertion(text)
        EditableInputReferenceStore.save(
            EditableInputReference(
                historyEntryID: historyEntryID,
                historyEntryRevision: historyEntryRevision,
                pendingHistoryMutationID: pendingHistoryMutationID,
                displayText: displayText,
                insertedText: text,
                postInsertionFingerprint: fieldContextProvider()?.deliveryFingerprint,
                extensionInstanceID: extensionInstanceID
            )
        )
        state.editAvailable = true
        state.assistantInsertionSucceeded = true
        successPulseTask?.cancel()
        successPulseTask = Task { @MainActor [weak state] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            state?.assistantInsertionSucceeded = false
        }
        let hint = ExtL10n.string("keyboard.edit.hint.available")
        editHintScheduler.show(
            message: hint,
            isPositive: true,
            duration: .seconds(10)
        )
    }

    private func clearEditHintIfPositive() {
        editHintScheduler.clearPositive()
    }

    private func clearLastInsertion() {
        lastInsertedText = nil
        state.undoAvailable = false
        state.editAvailable = false
        EditableInputReferenceStore.clear()
    }
}
