// ClipboardCaptureCoordinator.swift
// OSGKeyboard · Keyboard Extension
//
// Samples the general pasteboard on keyboard appear and while visible
// (changeCount-driven). Writes accepted text into ClipboardHistoryStore.

import Foundation
import UIKit
import OSGKeyboardShared

@MainActor
final class ClipboardCaptureCoordinator {
    private let state: KeyboardState
    private let history: ClipboardHistoryStore
    private var pollTimer: Timer?
    private var isSecureProvider: () -> Bool = { false }
    private var hasFullAccessProvider: () -> Bool = { false }

    init(
        state: KeyboardState,
        history: ClipboardHistoryStore = .shared
    ) {
        self.state = state
        self.history = history
    }

    func configure(
        isSecure: @escaping () -> Bool,
        hasFullAccess: @escaping () -> Bool
    ) {
        isSecureProvider = isSecure
        hasFullAccessProvider = hasFullAccess
    }

    func keyboardDidAppear() {
        history.reload()
        refreshSuggestionFromStore()
        captureIfNeeded(force: true)
        startPolling()
    }

    func keyboardWillDisappear() {
        stopPolling()
    }

    func refreshFlagsFromStore() {
        // Called from App Group poll — suggestion visibility may change.
        refreshSuggestionFromStore()
    }

    func openPanelFromTopButton() {
        if state.clipboardHistoryEnabled {
            history.reload()
            state.clipboardOverlay = .historyPanel
        } else {
            state.clipboardOverlay = .enableGuide
        }
    }

    func dismissOverlay() {
        state.clipboardOverlay = .none
    }

    func noteUserDidInputText() {
        clearSuggestion(persistDismiss: false)
    }

    func dismissSuggestion() {
        history.dismissSuggestion(forChangeCount: state.clipboardSuggestionChangeCount)
        clearSuggestion(persistDismiss: true)
    }

    func insertText(_ text: String, via insert: (String) -> Void) {
        insert(text)
        // Tapping a suggestion (or history row that shares this path) must not
        // resurface the same clipboard changeCount until the pasteboard changes.
        dismissSuggestion()
        dismissOverlay()
    }

    func clearHistory() {
        history.clearAll()
        clearSuggestion(persistDismiss: false)
    }

    func deleteEntry(id: UUID) {
        history.remove(id: id)
        refreshSuggestionFromStore()
    }

    // MARK: - Capture

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureIfNeeded(force: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func captureIfNeeded(force: Bool) {
        guard state.clipboardHistoryEnabled else {
            clearSuggestion(persistDismiss: false)
            return
        }
        guard hasFullAccessProvider() else { return }
        guard !isSecureProvider() else { return }

        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        if !force, changeCount == history.lastObservedChangeCount {
            refreshSuggestionFromStore()
            return
        }

        // Prefer hasStrings peek before reading body (reduces empty reads).
        guard pasteboard.hasStrings else {
            history.lastObservedChangeCount = changeCount
            refreshSuggestionFromStore()
            return
        }

        let raw = pasteboard.string
        if let entry = history.ingest(rawText: raw, changeCount: changeCount) {
            updateSuggestion(with: entry, changeCount: changeCount)
        } else {
            history.lastObservedChangeCount = changeCount
            refreshSuggestionFromStore()
        }
    }

    private func refreshSuggestionFromStore() {
        guard state.clipboardHistoryEnabled,
              state.clipboardCandidateBarEnabled,
              !isSecureProvider(),
              let newest = history.newestEntry
        else {
            clearSuggestion(persistDismiss: false)
            return
        }
        let changeCount = newest.changeCount ?? history.lastObservedChangeCount
        guard history.shouldShowSuggestion(
            forChangeCount: changeCount,
            candidateBarEnabled: state.clipboardCandidateBarEnabled,
            historyEnabled: state.clipboardHistoryEnabled
        ) else {
            clearSuggestion(persistDismiss: false)
            return
        }
        // Don't resurrect a strip the user already dismissed this session
        // unless changeCount advanced (handled in ingest).
        if state.clipboardSuggestionText == nil,
           let dismissed = history.suggestionDismissedChangeCount,
           dismissed == changeCount {
            return
        }
        state.clipboardSuggestionText = newest.text
        state.clipboardSuggestionChangeCount = changeCount
    }

    private func updateSuggestion(with entry: ClipboardHistoryEntry, changeCount: Int) {
        guard state.clipboardCandidateBarEnabled else {
            clearSuggestion(persistDismiss: false)
            return
        }
        // Already used/dismissed this pasteboard generation — keep it hidden.
        if history.suggestionDismissedChangeCount == changeCount {
            clearSuggestion(persistDismiss: false)
            return
        }
        state.clipboardSuggestionText = entry.text
        state.clipboardSuggestionChangeCount = changeCount
    }

    private func clearSuggestion(persistDismiss: Bool) {
        if persistDismiss {
            // already written in dismissSuggestion
        }
        state.clipboardSuggestionText = nil
        state.clipboardSuggestionChangeCount = nil
    }
}
