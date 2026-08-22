// KeyboardUsageTypingTests.swift
// OSGKeyboardExtTests
//
// Chinese preedit remains in the IME; only committed candidate text is counted.

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class KeyboardUsageTypingTests: XCTestCase {
    func testPinyinCompositionDoesNotCountLatinBeforeHanCommit() {
        let engine = KeyboardUsageRimeStub()
        let typing = TypingSessionController(engine: { engine })

        let first = typing.handleKey("n")
        let second = typing.handleKey("i")
        XCTAssertEqual(first, .none)
        XCTAssertEqual(second, .none)
        XCTAssertEqual(engine.composition.rawInput, "ni")

        let committed = typing.handleSpace()
        XCTAssertEqual(committed, .insert("你好"))
        let counts = KeyboardUsageCharacterClassifier.classify(committed.text)
        XCTAssertEqual(counts.chinese, 2)
        XCTAssertEqual(counts.english, 0)
        XCTAssertEqual(counts.other, 0)
    }
}

@MainActor
private final class KeyboardUsageRimeStub: RimeEngineBridging {
    private(set) var composition: TypingComposition = .empty
    var isReady = true
    var schema: TypingInputSchema = .fullPinyin

    func prepare() async throws {}

    func teardown() {
        composition = .empty
    }

    func setLanguage(_ language: TypingInputLanguage) {}

    @discardableResult
    func setSchema(_ schema: TypingInputSchema) -> Bool {
        self.schema = schema
        return true
    }

    func processCharacter(_ character: Character) -> String? {
        composition.rawInput.append(character)
        composition.preedit = composition.rawInput
        return nil
    }

    func processBackspace() -> String? {
        if !composition.rawInput.isEmpty {
            composition.rawInput.removeLast()
        }
        composition.preedit = composition.rawInput
        return nil
    }

    func processSpace() -> String? {
        composition = .empty
        return "你好"
    }

    func processReturn() -> String? {
        processSpace()
    }

    func selectCandidate(at index: Int) -> String {
        processSpace() ?? ""
    }

    func flushPreedit() -> String {
        let raw = composition.rawInput
        composition = .empty
        return raw
    }

    func clearComposition() {
        composition = .empty
    }
}
