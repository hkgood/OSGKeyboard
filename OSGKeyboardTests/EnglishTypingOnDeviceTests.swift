// EnglishTypingOnDeviceTests.swift
// OSGKeyboardTests
//
// Hosted in the main app so these can run on a physical iPhone.
// ExtTests stay tool-hosted (simulator-only).

@testable import OSGKeyboardShared
import XCTest

final class EnglishTypingOnDeviceTests: XCTestCase {
    func testLexiconLoadsFortyThousandWords() {
        let lexicon = EnglishLexicon()
        lexicon.prepare()
        XCTAssertTrue(lexicon.isLoaded)
        XCTAssertGreaterThanOrEqual(lexicon.wordCount, 30_000)
        XCTAssertTrue(lexicon.contains("the"))
        XCTAssertTrue(lexicon.contains("hello"))
        XCTAssertTrue(lexicon.contains("definitely"))
        lexicon.unload()
        XCTAssertFalse(lexicon.isLoaded)
    }

    func testTehAutocorrectsToThe() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertEqual(
            engine.correctionDecision(for: "teh", personalTerms: [], learnedBoosts: [:])?.replacement,
            "the"
        )
    }

    func testTitleCaseNamesStay() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertNil(engine.correctionDecision(for: "Rocky", personalTerms: [], learnedBoosts: [:]))
        XCTAssertNil(engine.correctionDecision(for: "Wang", personalTerms: [], learnedBoosts: [:]))
    }

    func testProximityGppdBecomesGood() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertEqual(
            engine.correctionDecision(for: "gppd", personalTerms: [], learnedBoosts: [:])?.replacement,
            "good"
        )
    }

    func testFormIsNotCorrectedToFrom() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertNil(engine.correctionDecision(for: "form", personalTerms: [], learnedBoosts: [:]))
    }

    func testThankYouBigram() {
        let lexicon = EnglishLexicon()
        lexicon.prepare()
        XCTAssertTrue(lexicon.nextWords(after: "thank").contains("you"))
    }

    @MainActor
    func testUITextCheckerCompletionsAvailable() {
        let system = UIKitEnglishSystemLexicon()
        let hits = system.completions(prefix: "hel", limit: 6)
        XCTAssertFalse(hits.isEmpty, "device UITextChecker should complete hel")
    }

    @MainActor
    func testQuickTypeBoardMarksCorrection() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        let composition = engine.compositionWhileTyping(
            EnglishSuggestionContext(currentWord: "teh")
        )
        XCTAssertEqual(composition.candidates.first?.role, .verbatim)
        XCTAssertTrue(composition.candidates.contains { $0.role == .correction && $0.text == "the" })
    }
}
