// CandidatePanelExpandTests.swift
// OSGKeyboard · Ext unit tests

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class CandidatePanelExpandTests: XCTestCase {
    func testDefaultConfigPageSizeMatchesExpandPool() {
        let yaml = RimeSchemaGenerator.defaultConfiguration()
        XCTAssertTrue(yaml.contains("page_size: 100"))
    }

    func testChevronRequiresChineseAndAtLeastTwoCandidates() {
        let engine = StubRimeEngine()
        let typing = TypingSessionController(engine: engine)

        XCTAssertFalse(typing.canExpandCandidatePanel)

        engine.composition = TypingComposition(
            preedit: "ni",
            candidates: [
                TypingCandidate(text: "你"),
                TypingCandidate(text: "泥")
            ]
        )
        // Composition is owned by the session; drive via processCharacter.
        _ = typing.handleKey("n")
        XCTAssertTrue(typing.canExpandCandidatePanel)
        XCTAssertEqual(typing.composition.candidates.count, 2)

        _ = typing.setLanguage(.english)
        XCTAssertFalse(typing.canExpandCandidatePanel)
        XCTAssertFalse(typing.isCandidatePanelExpanded)
    }

    func testToggleExpandAndSelectCollapses() {
        let engine = StubRimeEngine()
        let typing = TypingSessionController(engine: engine)

        _ = typing.handleKey("n")
        XCTAssertTrue(typing.canExpandCandidatePanel)

        typing.toggleCandidatePanelExpanded()
        XCTAssertTrue(typing.isCandidatePanelExpanded)

        typing.toggleCandidatePanelExpanded()
        XCTAssertFalse(typing.isCandidatePanelExpanded)

        typing.toggleCandidatePanelExpanded()
        XCTAssertTrue(typing.isCandidatePanelExpanded)

        let output = typing.selectCandidate(at: 0)
        XCTAssertEqual(output, .insert("你"))
        XCTAssertFalse(typing.isCandidatePanelExpanded)
    }

    func testPanelCollapsesWhenCandidatesDropBelowTwo() {
        let engine = StubRimeEngine()
        let typing = TypingSessionController(engine: engine)

        _ = typing.handleKey("n")
        typing.toggleCandidatePanelExpanded()
        XCTAssertTrue(typing.isCandidatePanelExpanded)

        // Backspace to a single-candidate (or empty) composition.
        engine.nextComposition = TypingComposition(
            preedit: "n",
            candidates: [TypingCandidate(text: "你")]
        )
        _ = typing.handleKey("⌫")
        XCTAssertFalse(typing.canExpandCandidatePanel)
        XCTAssertFalse(typing.isCandidatePanelExpanded)
    }

    func testLeaveTypingModeCollapsesPanel() {
        let engine = StubRimeEngine()
        let typing = TypingSessionController(engine: engine)
        _ = typing.handleKey("n")
        typing.toggleCandidatePanelExpanded()
        XCTAssertTrue(typing.isCandidatePanelExpanded)

        typing.leaveTypingMode()
        XCTAssertFalse(typing.isCandidatePanelExpanded)
        XCTAssertTrue(typing.composition.candidates.isEmpty)
    }
}

// Minimal engine that returns a two-candidate snapshot after any letter.
@MainActor
private final class StubRimeEngine: RimeEngineBridging {
    var composition: TypingComposition = .empty
    var isReady: Bool = true
    var schema: TypingInputSchema = .fullPinyin
    /// Optional override applied on the next processBackspace.
    var nextComposition: TypingComposition?

    func prepare() async throws {}
    func teardown() {
        composition = .empty
    }

    func setLanguage(_ language: TypingInputLanguage) {
        if language == .english {
            composition = .empty
        }
    }

    @discardableResult
    func setSchema(_ schema: TypingInputSchema) -> Bool {
        self.schema = schema
        return true
    }

    func processCharacter(_ character: Character) -> String? {
        composition = TypingComposition(
            preedit: String(character),
            candidates: [
                TypingCandidate(text: "你"),
                TypingCandidate(text: "泥")
            ]
        )
        return nil
    }

    func processBackspace() -> String? {
        if let next = nextComposition {
            composition = next
            nextComposition = nil
        } else {
            composition = .empty
        }
        return nil
    }

    func processSpace() -> String? {
        let text = composition.candidates.first?.text ?? " "
        composition = .empty
        return text
    }

    func processReturn() -> String? {
        composition = .empty
        return "\n"
    }

    func selectCandidate(at index: Int) -> String {
        guard composition.candidates.indices.contains(index) else { return "" }
        let text = composition.candidates[index].text
        composition = .empty
        return text
    }

    func flushPreedit() -> String {
        let raw = composition.preedit
        composition = .empty
        return raw
    }

    func clearComposition() {
        composition = .empty
    }
}
