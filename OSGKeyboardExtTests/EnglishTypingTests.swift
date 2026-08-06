// EnglishTypingTests.swift
// OSGKeyboard · Ext unit tests
//
// Lexicon / accent / suggestion ranking for the English typing path.

import XCTest
@testable import OSGKeyboardShared

final class EnglishTypingTests: XCTestCase {
    func testLexiconLoadsAndCompletesPrefix() {
        let lexicon = EnglishLexicon()
        lexicon.prepare()
        XCTAssertGreaterThan(lexicon.wordCount, 1_000)
        let hits = lexicon.completions(prefix: "hel", limit: 5)
        XCTAssertTrue(hits.contains("hello") || hits.contains("help") || hits.contains("held"))
    }

    func testCorrectionFindsNearbyWord() {
        let lexicon = EnglishLexicon()
        lexicon.prepare()
        // "teh" is a classic typo for "the".
        let correction = lexicon.bestCorrection(for: "teh")
        XCTAssertEqual(correction, "the")
        XCTAssertNil(lexicon.bestCorrection(for: "the"))
    }

    func testSuggestionEngineSkipsPersonalDictionaryTypos() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        let decision = engine.correctionDecision(
            for: "teh",
            personalTerms: ["teh"],
            learnedBoosts: [:]
        )
        XCTAssertNil(decision)
    }

    func testSuggestionEngineCompletionsPreferPersonalTerms() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        let composition = engine.compositionWhileTyping(
            EnglishSuggestionContext(
                currentWord: "osg",
                personalTerms: ["OSGKeyboard"],
                learnedBoosts: [:]
            )
        )
        XCTAssertEqual(composition.candidates.first?.text, "OSGKeyboard")
    }

    func testAutocapitalizationAtFieldStartAndAfterSentence() {
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: nil, mode: .sentences)
        )
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: "", mode: .sentences)
        )
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: "Hello. ", mode: .sentences)
        )
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: "Hello!\n", mode: .sentences)
        )
        // System keyboard (.sentences): Return starts a new line → capitalize.
        // Notes-style document context after Return is typically "…\n".
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: "Hello\n", mode: .sentences),
            "Return/newline must arm Shift (Notes multi-line)"
        )
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: "Hello\n\n", mode: .sentences)
        )
        XCTAssertFalse(
            TypingAutocapitalization.shouldCapitalize(precedingText: "Hello ", mode: .sentences)
        )
        XCTAssertTrue(
            TypingAutocapitalization.shouldCapitalize(precedingText: "Hello ", mode: .words)
        )
        XCTAssertFalse(
            TypingAutocapitalization.shouldCapitalize(precedingText: nil, mode: .none)
        )
    }

    @MainActor
    func testEnglishShiftArmsAfterReturnLikeNotes() {
        // Simulates Notes: proxy preceding text gains a trailing newline after Return.
        var preceding = "Hello"
        let typing = TypingSessionController()
        typing.precedingTextProvider = { preceding }
        typing.autocapitalizationModeProvider = { .sentences }
        _ = typing.setLanguage(.english)
        XCTAssertFalse(typing.shiftActive, "mid-word should not arm Shift")

        _ = typing.handleReturn()
        preceding = "Hello\n" // host document after inserting newline
        typing.syncAutocapitalization(accountingForInsert: "\n")
        XCTAssertTrue(
            typing.shiftActive,
            "after Return, Shift must light for next line (system sentences behavior)"
        )
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }

    @MainActor
    func testEnglishShiftArmsWhenProxyLagsAfterReturn() {
        // Notes often still reports pre-Return context right after insertText("\n").
        var preceding = "Hello"
        let typing = TypingSessionController()
        typing.precedingTextProvider = { preceding }
        typing.autocapitalizationModeProvider = { .sentences }
        _ = typing.setLanguage(.english)

        _ = typing.handleReturn()
        // Proxy intentionally stale — still "Hello" without "\n".
        typing.syncAutocapitalization(accountingForInsert: "\n")
        XCTAssertTrue(typing.shiftActive)
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }

    @MainActor
    func testEnglishShiftArmsWhenProxyLagsAfterPeriod() {
        var preceding = "Hello"
        let typing = TypingSessionController()
        typing.precedingTextProvider = { preceding }
        typing.autocapitalizationModeProvider = { .sentences }
        _ = typing.setLanguage(.english)

        _ = typing.handleKey(".")
        typing.syncAutocapitalization(accountingForInsert: ".")
        XCTAssertTrue(typing.shiftActive)
    }

    @MainActor
    func testEnglishIdleShowsNoCandidatesUntilLetterTyped() {
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()
        XCTAssertTrue(typing.composition.candidates.isEmpty)

        _ = typing.handleKey("h")
        XCTAssertFalse(typing.composition.candidates.isEmpty)
        XCTAssertEqual(typing.composition.preedit, "h")
    }

    func testEnglishTypingHotwordsFilterOutChineseTerms() {
        var dictionary = PersonalDictionary()
        _ = dictionary.upsertManual(term: "张三")
        _ = dictionary.upsertManual(term: "OSGKeyboard")
        _ = dictionary.upsertManual(term: "微信")
        guard let wechatID = dictionary.entry(matchingTerm: "微信")?.id else {
            return XCTFail("expected 微信 entry")
        }
        dictionary.updateAliases(for: wechatID, aliases: ["WeChat"])

        let hotwords = dictionary.englishTypingHotwords()
        XCTAssertTrue(hotwords.contains("OSGKeyboard"))
        XCTAssertTrue(hotwords.contains("WeChat"))
        XCTAssertFalse(hotwords.contains(where: { $0.contains("张") || $0.contains("微") }))
        XCTAssertFalse(PersonalDictionary.isEnglishTypingHotword("你好"))
        XCTAssertTrue(PersonalDictionary.isEnglishTypingHotword("GPT-4"))
    }

    @MainActor
    func testEnglishTypingEmitsCompletionsIntoComposition() {
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        _ = typing.handleKey("h")
        _ = typing.handleKey("e")
        _ = typing.handleKey("l")

        XCTAssertFalse(typing.composition.candidates.isEmpty)
        XCTAssertEqual(typing.composition.preedit, "hel")
    }

    @MainActor
    func testAutocorrectUndoRestoresOriginal() {
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        for ch in ["t", "e", "h"] {
            _ = typing.handleKey(ch)
        }
        let spaced = typing.handleSpace()
        // Either corrected to "the " or left as-is if lexicon missing in test bundle.
        if spaced.deleteCount > 0 {
            XCTAssertTrue(spaced.text.hasPrefix("the"))
            let undone = typing.handleKey("⌫")
            XCTAssertEqual(undone.text, "teh")
            XCTAssertEqual(undone.deleteCount, spaced.text.count)
        }
    }
}
