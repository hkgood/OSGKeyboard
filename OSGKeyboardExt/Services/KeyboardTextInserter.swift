// KeyboardTextInserter.swift
// OSGKeyboard · Keyboard Extension
//
// Inserts Flow transcripts from the host app and surfaces polish warnings
// without re-running LLM polish in the extension.

import OSGKeyboardShared

@MainActor
final class KeyboardTextInserter {
    private let state: KeyboardState
    private let insertText: (String) -> Void
    private let scheduleAutoClearError: () -> Void

    init(
        state: KeyboardState,
        insertText: @escaping (String) -> Void,
        scheduleAutoClearError: @escaping () -> Void
    ) {
        self.state = state
        self.insertText = insertText
        self.scheduleAutoClearError = scheduleAutoClearError
    }

    func handleFlowTranscript(_ delivery: TranscriptionDelivery) {
        let trimmed = delivery.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.phase = .idle
            state.level = 0
            return
        }
        // Host app already polished when configured; keyboard only inserts.
        insertText(trimmed)
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
}
