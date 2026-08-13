// ClipboardSuggestionLifecycleTests.swift
// OSGKeyboard · Keyboard Extension Tests
//
// Verifies that the transient suggestion belongs to one pasteboard generation
// and one keyboard presentation; clipboard history remains independently usable.

import Combine
import XCTest
@testable import OSGKeyboardShared

@MainActor
final class ClipboardSuggestionLifecycleTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var state: KeyboardState!
    private var history: ClipboardHistoryStore!
    private var pasteboard: FakeClipboardPasteboard!
    private var coordinator: ClipboardCaptureCoordinator!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardSuggestionLifecycleTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        state = KeyboardState()
        state.clipboardHistoryEnabled = true
        state.clipboardCandidateBarEnabled = true
        history = ClipboardHistoryStore(defaults: defaults)
        history.lastObservedChangeCount = 10
        pasteboard = FakeClipboardPasteboard(changeCount: 10)
        coordinator = ClipboardCaptureCoordinator(
            state: state,
            history: history,
            pasteboard: pasteboard
        )
        coordinator.configure(isSecure: { false }, hasFullAccess: { true })
    }

    override func tearDown() {
        coordinator.keyboardWillDisappear()
        coordinator = nil
        pasteboard = nil
        history = nil
        state = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testNewAcceptedCopyShowsSuggestion() {
        copy("a fresh sentence")

        coordinator.captureIfNeeded()

        XCTAssertEqual(state.clipboardSuggestionText, "a fresh sentence")
        XCTAssertEqual(state.clipboardSuggestionChangeCount, 11)
    }

    func testTypingEndsSuggestionForSameGeneration() {
        copy("meeting notes")
        coordinator.captureIfNeeded()

        coordinator.noteUserDidInputText()
        coordinator.captureIfNeeded()

        XCTAssertNil(state.clipboardSuggestionText)
        XCTAssertEqual(history.suggestionDismissedChangeCount, 11)
    }

    func testKeyboardDismissalEndsSuggestionForSameGeneration() {
        copy("shipping address")
        coordinator.captureIfNeeded()

        coordinator.keyboardWillDisappear()
        coordinator.keyboardDidAppear()

        XCTAssertNil(state.clipboardSuggestionText)
        XCTAssertEqual(history.suggestionDismissedChangeCount, 11)
    }

    func testKeyboardAppearancePrimesPasteAccessWithoutRepublishingCurrentGeneration() {
        pasteboard.setText("already observed", changeCount: 10)

        coordinator.keyboardDidAppear()

        XCTAssertEqual(pasteboard.stringReadCount, 1)
        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(state.clipboardSuggestionText)
    }

    func testRejectedNewCopyClearsInsteadOfReplayingHistory() {
        copy("draft reply")
        coordinator.captureIfNeeded()

        copy("482913")
        coordinator.captureIfNeeded()

        XCTAssertNil(state.clipboardSuggestionText)
        XCTAssertEqual(history.entries.map(\.text), ["draft reply"])
        XCTAssertEqual(history.lastObservedChangeCount, 12)
    }

    func testNonTextGenerationClearsInsteadOfReplayingHistory() {
        copy("draft reply")
        coordinator.captureIfNeeded()

        pasteboard.setNonText(changeCount: 12)
        coordinator.captureIfNeeded()

        XCTAssertNil(state.clipboardSuggestionText)
        XCTAssertEqual(history.entries.map(\.text), ["draft reply"])
        XCTAssertEqual(history.lastObservedChangeCount, 12)
    }

    func testEnablingCandidateBarDoesNotReplayHistory() {
        state.clipboardCandidateBarEnabled = false
        history.ingest(rawText: "old history item", changeCount: 9)

        state.clipboardCandidateBarEnabled = true
        coordinator.refreshFlagsFromStore()

        XCTAssertNil(state.clipboardSuggestionText)
    }

    func testDeletingCurrentEntryDoesNotPromoteOlderHistory() throws {
        history.ingest(rawText: "older item", changeCount: 9)
        copy("current item")
        coordinator.captureIfNeeded()
        let currentID = try XCTUnwrap(history.newestEntry?.id)

        coordinator.deleteEntry(id: currentID)

        XCTAssertNil(state.clipboardSuggestionText)
        XCTAssertEqual(history.entries.map(\.text), ["older item"])
    }

    func testUnchangedPollingDoesNotRepublishSuggestion() {
        copy("stable clipboard")
        coordinator.captureIfNeeded()
        var publications = 0
        let cancellable = state.$clipboardSuggestionText
            .dropFirst()
            .sink { _ in publications += 1 }
        defer { cancellable.cancel() }

        coordinator.captureIfNeeded()
        coordinator.captureIfNeeded()
        coordinator.captureIfNeeded()

        XCTAssertEqual(publications, 0)
        XCTAssertEqual(pasteboard.stringReadCount, 1)
    }

    func testClearHistoryEndsSuggestionBeforeRemovingEntries() {
        history.ingest(rawText: "older item", changeCount: 9)
        copy("current item")
        coordinator.captureIfNeeded()

        coordinator.clearHistory()

        XCTAssertTrue(history.entries.isEmpty)
        XCTAssertNil(state.clipboardSuggestionText)
        XCTAssertNil(state.clipboardSuggestionChangeCount)
        XCTAssertEqual(history.suggestionDismissedChangeCount, 11)
    }

    func testExplicitDismissAndInsertRemainTerminal() {
        copy("dismiss once")
        coordinator.captureIfNeeded()
        coordinator.dismissSuggestion()
        coordinator.captureIfNeeded()
        XCTAssertNil(state.clipboardSuggestionText)

        copy("insert once")
        coordinator.captureIfNeeded()
        coordinator.insertText("insert once", via: { _ in })
        coordinator.captureIfNeeded()
        XCTAssertNil(state.clipboardSuggestionText)
    }

    func testSecureFieldTransitionEndsSuggestion() {
        copy("private note")
        coordinator.captureIfNeeded()

        coordinator.secureEntryDidChange(isSecure: true)
        coordinator.secureEntryDidChange(isSecure: false)
        coordinator.captureIfNeeded()

        XCTAssertNil(state.clipboardSuggestionText)
    }

    private func copy(_ text: String) {
        pasteboard.setText(text, changeCount: pasteboard.changeCount + 1)
    }
}

@MainActor
private final class FakeClipboardPasteboard: ClipboardPasteboardProviding {
    private(set) var changeCount: Int
    private(set) var hasStrings = false
    private var storedString: String?
    private(set) var stringReadCount = 0

    var string: String? {
        stringReadCount += 1
        return storedString
    }

    init(changeCount: Int) {
        self.changeCount = changeCount
    }

    func setText(_ text: String, changeCount: Int) {
        self.changeCount = changeCount
        hasStrings = true
        storedString = text
    }

    func setNonText(changeCount: Int) {
        self.changeCount = changeCount
        hasStrings = false
        storedString = nil
    }
}
