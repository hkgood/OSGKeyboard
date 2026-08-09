// KeyboardTextInserter.swift
// OSGKeyboard · Keyboard Extension
//
// Inserts Flow transcripts from the host app and surfaces polish warnings
// without re-running LLM polish in the extension. Also tracks the last
// voice insertion so the undo button can roll it back safely.

import OSGKeyboardShared

@MainActor
final class KeyboardTextInserter {
    private let state: KeyboardState
    private let insertText: (String) -> Void
    private let deleteBackward: () -> Void
    private let contextBeforeInput: () -> String?
    private let scheduleAutoClearError: () -> Void

    /// Exact string last inserted by voice (including any word-boundary
    /// separator). Cleared after a successful undo or when the caret no
    /// longer sits after that text.
    private var lastInsertedText: String?
    /// Suppresses availability refresh while we walk `deleteBackward`
    /// for undo, so intermediate contexts don't flicker the button.
    private var isUndoing = false

    init(
        state: KeyboardState,
        insertText: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        contextBeforeInput: @escaping () -> String?,
        scheduleAutoClearError: @escaping () -> Void
    ) {
        self.state = state
        self.insertText = insertText
        self.deleteBackward = deleteBackward
        self.contextBeforeInput = contextBeforeInput
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
        recordLastInsertion(inserted)
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
        clearLastInsertion()
        OSGLog.keyboardExt.info("voice undo length=\(text.count, privacy: .public)")
    }

    /// Re-evaluate whether the recorded insertion is still undoable.
    /// Call from `textDidChange` / `selectionDidChange`.
    func refreshUndoAvailability() {
        guard !isUndoing else { return }
        guard let text = lastInsertedText, !text.isEmpty else {
            if state.undoAvailable { state.undoAvailable = false }
            return
        }
        let available = contextBeforeInput()?.hasSuffix(text) == true
        if !available {
            // Caret moved or the user edited the insertion — drop the record.
            lastInsertedText = nil
        }
        if state.undoAvailable != available {
            state.undoAvailable = available
        }
    }

    private func recordLastInsertion(_ text: String) {
        lastInsertedText = text
        state.undoAvailable = true
    }

    private func clearLastInsertion() {
        lastInsertedText = nil
        state.undoAvailable = false
    }
}
