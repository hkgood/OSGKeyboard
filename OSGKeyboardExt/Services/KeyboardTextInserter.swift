// KeyboardTextInserter.swift
// OSGKeyboard · Keyboard Extension
//
// Inserts Flow transcripts from the host app and surfaces polish warnings
// without re-running LLM polish in the extension. Also tracks the last
// voice insertion so the undo button can roll it back safely.

import UIKit
import OSGKeyboardShared

@MainActor
final class KeyboardTextInserter {
    private let state: KeyboardState
    private let insertText: (String) -> Void
    private let deleteBackward: () -> Void
    private let contextBeforeInput: () -> String?
    private let fieldContextProvider: () -> FlowFieldContext?
    private let selectedText: () -> String?
    private let scheduleAutoClearError: () -> Void

    /// Exact string last inserted by voice (including any word-boundary
    /// separator). Cleared after a successful undo or when the caret no
    /// longer sits after that text.
    private var lastInsertedText: String?
    /// Text captured when the last insertion was undone, so redo can
    /// re-apply it. Cleared by any new insertion or external edit.
    private var redoText: String?
    private var redoContextBefore: String?
    private let extensionInstanceID = UUID()
    private var lastEditUndo: PendingTextEditTransaction?
    private var editHintTask: Task<Void, Never>?
    /// Suppresses availability refresh while we walk `deleteBackward`
    /// for undo, so intermediate contexts don't flicker the button.
    private var isUndoing = false

    init(
        state: KeyboardState,
        insertText: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        contextBeforeInput: @escaping () -> String?,
        fieldContextProvider: @escaping () -> FlowFieldContext?,
        selectedText: @escaping () -> String?,
        scheduleAutoClearError: @escaping () -> Void
    ) {
        self.state = state
        self.insertText = insertText
        self.deleteBackward = deleteBackward
        self.contextBeforeInput = contextBeforeInput
        self.fieldContextProvider = fieldContextProvider
        self.selectedText = selectedText
        self.scheduleAutoClearError = scheduleAutoClearError
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
        insertText(inserted)
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

    /// Roll back the last voice insertion when it is still at the caret.
    func undoLastInsertion() {
        if undoLastEditIfPossible() {
            return
        }
        guard let text = lastInsertedText, !text.isEmpty else { return }
        guard let preceding = contextBeforeInput(), preceding.hasSuffix(text) else {
            clearLastInsertion()
            return
        }

        isUndoing = true
        defer { isUndoing = false }

        for _ in 0..<text.count {
            deleteBackward()
        }
        // Stash the exact inserted string (incl. separator) for redo before
        // dropping the live undo record.
        redoText = text
        redoContextBefore = contextBeforeInput()
        lastInsertedText = nil
        state.undoAvailable = false
        OSGLog.keyboardExt.info("voice undo length=\(text.count, privacy: .public)")
    }

    /// Re-apply the last undone voice insertion when it is still absent from
    /// the caret (i.e. the undo was not overwritten by an external edit).
    func redoLastInsertion() {
        guard let text = redoText, !text.isEmpty,
              contextBeforeInput() == redoContextBefore else {
            redoText = nil
            redoContextBefore = nil
            state.redoAvailable = false
            return
        }
        guard let preceding = contextBeforeInput(), !preceding.hasSuffix(text) else {
            redoText = nil
            state.redoAvailable = false
            return
        }
        insertText(text)
        lastInsertedText = text
        redoText = nil
        redoContextBefore = nil
        state.undoAvailable = true
        OSGLog.keyboardExt.info("voice redo length=\(text.count, privacy: .public)")
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
                let available = contextBeforeInput()?.hasSuffix(text) == true
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
        guard reference.postInsertionFingerprint == nil
                || reference.postInsertionFingerprint
                    == fieldContextProvider()?.deliveryFingerprint else {
            return nil
        }
        if reference.extensionInstanceID == extensionInstanceID,
           lastInsertedText == reference.insertedText {
            return reference
        }
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
        insertText(inserted)
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
        lastEditUndo = transaction
        recordLastInsertion(
            inserted,
            displayText: result,
            historyEntryID: historyEntryID,
            historyEntryRevision: historyAction == .update
                ? (source.historyEntryRevision ?? 0) + 1
                : 0,
            pendingHistoryMutationID: mutation.id
        )
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
        guard let transaction = lastEditUndo,
              let preceding = contextBeforeInput() else {
            return false
        }
        let insertedAfter = lastInsertedText ?? transaction.afterText
        guard preceding.hasSuffix(insertedAfter) else {
            lastEditUndo = nil
            return false
        }
        for _ in insertedAfter {
            deleteBackward()
        }

        switch transaction.deliveryMode {
        case .replace:
            insertText(transaction.beforeText)
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

    private func recordLastInsertion(
        _ text: String,
        displayText: String,
        historyEntryID: UUID?,
        historyEntryRevision: Int64?,
        pendingHistoryMutationID: UUID?
    ) {
        lastInsertedText = text
        redoText = nil
        redoContextBefore = nil
        state.undoAvailable = true
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
        editHintTask?.cancel()
        let hint = ExtL10n.string("keyboard.edit.hint.available")
        state.editHint = hint
        state.editHintIsPositive = true
        editHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled,
                  self?.state.editHint == hint,
                  self?.state.editHintIsPositive == true else {
                return
            }
            self?.state.editHint = nil
            self?.state.editHintIsPositive = false
        }
    }

    private func clearLastInsertion() {
        lastInsertedText = nil
        state.undoAvailable = false
        EditableInputReferenceStore.clear()
    }
}
