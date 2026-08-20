// ClipboardCaptureCoordinator.swift
// OSGKeyboard · Keyboard Extension
//
// Samples the general pasteboard on keyboard appear and while visible
// (changeCount-driven). Writes accepted text into ClipboardHistoryStore.

import Foundation
import OSGKeyboardShared
import UIKit

@MainActor
protocol ClipboardPasteboardProviding: AnyObject {
    var changeCount: Int { get }
    var hasStrings: Bool { get }
    var string: String? { get }
}

@MainActor
final class SystemClipboardPasteboard: ClipboardPasteboardProviding {
    var changeCount: Int { UIPasteboard.general.changeCount }
    var hasStrings: Bool { UIPasteboard.general.hasStrings }
    var string: String? { UIPasteboard.general.string }
}

@MainActor
final class ClipboardCaptureCoordinator {
    /// Universal Clipboard may synchronously fetch from another device for
    /// seconds. System pasteboard reads must never block keyboard presentation.
    private static let readQueue = DispatchQueue(
        label: "com.osgkeyboard.clipboard.read",
        qos: .utility
    )
    private static let pollInterval: TimeInterval = 0.8

    private let state: KeyboardState
    private let history: ClipboardHistoryStore
    private let pasteboard: ClipboardPasteboardProviding
    private var pollTimer: Timer?
    private var isSecureProvider: () -> Bool = { false }
    private var hasFullAccessProvider: () -> Bool = { false }
    /// Ephemeral only: leaving a secure field must not resurrect old body text.
    private var secureFieldSuppressedChangeCount: Int?
    private var isSecureEntryActive = false
    private var isSampling = false
    private var forcesNextSample = true
    private var isKeyboardVisible = false

    init(
        state: KeyboardState,
        history: ClipboardHistoryStore = .shared,
        pasteboard: ClipboardPasteboardProviding = SystemClipboardPasteboard()
    ) {
        self.state = state
        self.history = history
        self.pasteboard = pasteboard
    }

    func configure(
        isSecure: @escaping () -> Bool,
        hasFullAccess: @escaping () -> Bool
    ) {
        isSecureProvider = isSecure
        hasFullAccessProvider = hasFullAccess
    }

    func keyboardDidAppear() {
        isKeyboardVisible = true
        KeyboardExtensionMemoryTelemetry.record(
            "clipboard.reload.begin",
            details: "enabled=\(state.clipboardHistoryEnabled ? 1 : 0) "
                + "entries=\(history.entries.count)"
        )
        history.reload()
        KeyboardExtensionMemoryTelemetry.record(
            "clipboard.reload.done",
            details: "enabled=\(state.clipboardHistoryEnabled ? 1 : 0) "
                + "entries=\(history.entries.count)"
        )
        // A suggestion belongs to one keyboard presentation. Clear any
        // presentation state left behind by a reused extension controller.
        endCurrentSuggestion()
        forcesNextSample = true
        // Delay the system pasteboard read until the first poll tick. A
        // Universal Clipboard fetch or paste alert during the appear sequence
        // can otherwise freeze the keyboard before SwiftUI draws.
        if !(pasteboard is SystemClipboardPasteboard) {
            captureIfNeeded(forceRead: true)
        }
        startPolling()
    }

    func keyboardWillDisappear() {
        isKeyboardVisible = false
        stopPolling()
        // A1 policy: closing the keyboard ends this generation's suggestion.
        endCurrentSuggestion()
    }

    func refreshFlagsFromStore() {
        // Settings changes may hide the active suggestion, but enabling the
        // strip must wait for a new pasteboard generation.
        if !state.clipboardHistoryEnabled || !state.clipboardCandidateBarEnabled {
            endCurrentSuggestion()
        }
    }

    func secureEntryDidChange(isSecure: Bool) {
        if isSecure {
            isSecureEntryActive = true
            secureFieldSuppressedChangeCount = pasteboard.changeCount
        } else if isSecureEntryActive {
            // Capture the latest generation once more on exit so a pasteboard
            // change near the secure-field transition cannot be persisted.
            secureFieldSuppressedChangeCount = pasteboard.changeCount
            isSecureEntryActive = false
        } else {
            return
        }
        endCurrentSuggestion()
        state.clipboardOverlay = .none
    }

    func openPanelFromTopButton() {
        guard state.canShowClipboardEntry else { return }
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
        endCurrentSuggestion()
    }

    func dismissSuggestion() {
        endCurrentSuggestion()
    }

    func insertText(_ text: String, via insert: (String) -> Void) {
        guard state.canShowClipboardEntry else { return }
        insert(text)
        // Tapping a suggestion (or history row that shares this path) must not
        // resurface the same clipboard changeCount until the pasteboard changes.
        dismissSuggestion()
        dismissOverlay()
    }

    func clearHistory() {
        endCurrentSuggestion()
        history.clearAll()
    }

    func deleteEntry(id: UUID) {
        let deletedChangeCount = history.entries.first(where: { $0.id == id })?.changeCount
        history.remove(id: id)
        if deletedChangeCount == state.clipboardSuggestionChangeCount {
            endCurrentSuggestion()
        }
    }

    // MARK: - Capture

    private func startPolling() {
        stopPolling()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureIfNeeded()
            }
        }
        timer.tolerance = Self.pollInterval / 4
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func captureIfNeeded(forceRead: Bool = false) {
        guard state.clipboardHistoryEnabled else {
            endCurrentSuggestion()
            return
        }
        #if DEBUG
        // What's New demo seeds history itself — never touch the pasteboard
        // (avoids the simulator “允许粘贴” alert mid-recording).
        if WhatsNewDemoScenario.peek() != nil || WhatsNewDemoScenario.isPlaying() {
            return
        }
        #endif
        guard hasFullAccessProvider() else { return }
        guard !isSecureProvider() else {
            secureEntryDidChange(isSecure: true)
            return
        }

        if pasteboard is SystemClipboardPasteboard {
            beginSystemSample(forceRead: forceRead || forcesNextSample)
            forcesNextSample = false
            return
        }
        captureInjectedPasteboard(forceRead: forceRead)
    }

    /// Synchronous path retained for deterministic tests and injected fakes.
    /// Production always uses `beginSystemSample` below.
    private func captureInjectedPasteboard(forceRead: Bool) {
        let changeCount = pasteboard.changeCount
        if ClipboardHistoryPolicy.shouldSuppressCapture(
            changeCount: changeCount,
            secureFieldSuppressedChangeCount: secureFieldSuppressedChangeCount
        ) {
            history.lastObservedChangeCount = changeCount
            clearSuggestion()
            return
        }
        secureFieldSuppressedChangeCount = nil
        let isCurrentGeneration = changeCount == history.lastObservedChangeCount
        if isCurrentGeneration && !forceRead {
            return
        }

        // A new generation replaces any previous transient suggestion,
        // including generations that contain no acceptable text.
        clearSuggestion()

        // Prefer hasStrings peek before reading body (reduces empty reads).
        guard pasteboard.hasStrings else {
            history.lastObservedChangeCount = changeCount
            return
        }

        let raw = pasteboard.string
        // The forced appearance read exists only to establish/refresh iOS
        // paste permission. It must not reinsert or republish old content.
        if isCurrentGeneration {
            return
        }
        if let entry = history.ingest(rawText: raw, changeCount: changeCount) {
            updateSuggestion(with: entry, changeCount: changeCount)
        } else {
            history.lastObservedChangeCount = changeCount
        }
    }

    private struct Sample: Sendable {
        let changeCount: Int
        let hasStrings: Bool
        let text: String?
    }

    private func beginSystemSample(forceRead: Bool) {
        guard !isSampling else { return }
        isSampling = true
        let lastObserved = history.lastObservedChangeCount

        Self.readQueue.async {
            let pasteboard = UIPasteboard.general
            let changeCount = pasteboard.changeCount
            guard forceRead || changeCount != lastObserved else {
                Task { @MainActor [weak self] in
                    self?.isSampling = false
                }
                return
            }
            let hasStrings = pasteboard.hasStrings
            let sample = Sample(
                changeCount: changeCount,
                hasStrings: hasStrings,
                text: hasStrings ? pasteboard.string : nil
            )
            Task { @MainActor [weak self] in
                self?.finishSystemSample(sample)
            }
        }
    }

    private func finishSystemSample(_ sample: Sample) {
        isSampling = false
        guard isKeyboardVisible,
              state.clipboardHistoryEnabled,
              hasFullAccessProvider(),
              !isSecureProvider()
        else { return }

        let changeCount = sample.changeCount
        if ClipboardHistoryPolicy.shouldSuppressCapture(
            changeCount: changeCount,
            secureFieldSuppressedChangeCount: secureFieldSuppressedChangeCount
        ) {
            history.lastObservedChangeCount = changeCount
            clearSuggestion()
            return
        }
        secureFieldSuppressedChangeCount = nil
        let isCurrentGeneration = changeCount == history.lastObservedChangeCount

        // A new generation replaces any previous transient suggestion,
        // including generations that contain no acceptable text.
        clearSuggestion()
        guard sample.hasStrings else {
            history.lastObservedChangeCount = changeCount
            return
        }
        // Forced appearance reads establish iOS paste permission only. Never
        // republish content from an already observed generation.
        guard !isCurrentGeneration else { return }

        if let entry = history.ingest(rawText: sample.text, changeCount: changeCount) {
            updateSuggestion(with: entry, changeCount: changeCount)
        } else {
            history.lastObservedChangeCount = changeCount
        }
    }

    private func updateSuggestion(with entry: ClipboardHistoryEntry, changeCount: Int) {
        guard state.canShowClipboardEntry,
              state.clipboardCandidateBarEnabled,
              changeCount != secureFieldSuppressedChangeCount
        else {
            clearSuggestion()
            return
        }
        // Already used/dismissed this pasteboard generation — keep it hidden.
        if history.suggestionDismissedChangeCount == changeCount {
            clearSuggestion()
            return
        }
        state.clipboardSuggestionText = entry.text
        state.clipboardSuggestionChangeCount = changeCount
    }

    private func endCurrentSuggestion() {
        history.dismissSuggestion(forChangeCount: state.clipboardSuggestionChangeCount)
        clearSuggestion()
    }

    private func clearSuggestion() {
        guard state.clipboardSuggestionText != nil
                || state.clipboardSuggestionChangeCount != nil
        else {
            return
        }
        state.clipboardSuggestionText = nil
        state.clipboardSuggestionChangeCount = nil
    }
}
