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
        XCTAssertTrue(lexicon.isLoaded)
        XCTAssertGreaterThan(lexicon.wordCount, 10_000)
        let hits = lexicon.completions(prefix: "hel", limit: 5)
        XCTAssertTrue(hits.contains("hello") || hits.contains("help") || hits.contains("held"))
        lexicon.unload()
        XCTAssertFalse(lexicon.isLoaded)
        XCTAssertEqual(lexicon.wordCount, 0)
    }

    @MainActor
    func testChineseTypingDoesNotLoadEnglishLexicon() {
        EnglishLexicon.shared.unload()
        let typing = TypingSessionController()
        _ = typing.setLanguage(.chinese)
        typing.enterTypingMode()
        XCTAssertFalse(EnglishLexicon.shared.isLoaded)
        _ = typing.setLanguage(.english)
        XCTAssertTrue(EnglishLexicon.shared.isLoaded)
        _ = typing.setLanguage(.chinese)
        XCTAssertFalse(EnglishLexicon.shared.isLoaded)
        typing.leaveTypingMode()
    }

    func testCorrectionFindsNearbyWord() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        // "teh" leaks into web unigrams; the engine must still treat it as a typo.
        let decision = engine.correctionDecision(
            for: "teh",
            personalTerms: [],
            learnedBoosts: [:]
        )
        XCTAssertEqual(decision?.replacement, "the")
        XCTAssertNil(
            engine.correctionDecision(for: "the", personalTerms: [], learnedBoosts: [:])
        )
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
        XCTAssertEqual(composition.candidates.first?.role, .verbatim)
        XCTAssertEqual(composition.candidates.first?.text, "osg")
        XCTAssertTrue(composition.candidates.contains { $0.text == "OSGKeyboard" })
    }

    func testSuggestionEngineReturnsNoCandidatesWithoutCurrentWord() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        let composition = engine.compositionWhileTyping(
            EnglishSuggestionContext(
                previousWord: "hello",
                personalTerms: ["OSGKeyboard"]
            )
        )

        XCTAssertEqual(composition, .empty)
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
    func testOldWordBackspaceRehydratesSuggestionsFromDocumentContext() {
        var preceding = "board"
        let following = "\n"
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        typing.precedingTextProvider = { preceding }
        typing.followingTextProvider = { following }
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()
        typing.synchronizeEnglishDocumentContext(caretMoved: true)

        func apply(_ output: TypingOutput) {
            for _ in 0..<output.deleteCount {
                if !preceding.isEmpty { preceding.removeLast() }
            }
            preceding += output.text
            typing.syncAutocapitalization(
                accountingForInsert: output.text,
                deleteCount: output.deleteCount
            )
        }

        apply(typing.handleKey("⌫"))
        XCTAssertEqual(preceding, "boar")
        XCTAssertEqual(typing.composition.preedit, "boar")

        apply(typing.handleKey("⌫"))
        XCTAssertEqual(preceding, "boa")
        XCTAssertEqual(typing.composition.preedit, "boa")
        XCTAssertTrue(
            typing.composition.candidates.contains {
                $0.text.compare("board", options: .caseInsensitive) == .orderedSame
            }
        )

        apply(typing.handleKey("t"))
        XCTAssertEqual(preceding, "boat")
        XCTAssertEqual(typing.composition.preedit.lowercased(), "boat")
    }

    @MainActor
    func testCandidateReplacementRejectsStaleDocumentAnchor() {
        var preceding = ""
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        typing.precedingTextProvider = { preceding }
        typing.followingTextProvider = { "" }
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        for key in ["b", "o", "a"] {
            let output = typing.handleKey(key)
            preceding += output.text
            typing.syncAutocapitalization(accountingForInsert: output.text)
        }
        guard let boardIndex = typing.composition.candidates.firstIndex(where: {
            $0.text.compare("board", options: .caseInsensitive) == .orderedSame
        }) else {
            return XCTFail("expected board completion")
        }

        preceding = "board"
        let output = typing.selectCandidate(at: boardIndex)

        XCTAssertEqual(output, .none)
        XCTAssertEqual(typing.composition.preedit.lowercased(), "board")
    }

    @MainActor
    func testMidWordCaretSuppressesUnsafeBackwardOnlyReplacement() {
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        typing.precedingTextProvider = { "boa" }
        typing.followingTextProvider = { "rd" }
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        typing.synchronizeEnglishDocumentContext(caretMoved: true)

        XCTAssertTrue(typing.composition.candidates.isEmpty)
        XCTAssertTrue(typing.composition.preedit.isEmpty)
    }

    @MainActor
    func testStaleHostCallbackDoesNotDiscardLocalEnglishWord() {
        var preceding = ""
        let typing = TypingSessionController()
        typing.suggestionsEnabled = true
        typing.precedingTextProvider = { preceding }
        typing.followingTextProvider = { "" }
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        let output = typing.handleKey("h")
        typing.syncAutocapitalization(accountingForInsert: output.text)
        typing.synchronizeEnglishDocumentContext(caretMoved: true)

        XCTAssertEqual(typing.composition.preedit.lowercased(), "h")

        preceding = "h"
        typing.synchronizeEnglishDocumentContext()
        XCTAssertEqual(typing.composition.preedit.lowercased(), "h")
    }

    @MainActor
    func testAutocorrectUndoRestoresOriginal() {
        let typing = makeIsolatedEnglishSession(suite: "english.undo.test")

        for ch in ["t", "e", "h"] {
            _ = typing.handleKey(ch)
        }
        let spaced = typing.handleSpace()
        XCTAssertEqual(spaced.deleteCount, 3)
        XCTAssertTrue(spaced.text.hasPrefix("the"))
        let undone = typing.handleKey("⌫")
        XCTAssertEqual(undone.text, "teh")
        XCTAssertEqual(undone.deleteCount, spaced.text.count)
    }

    @MainActor
    func testPeriodShortcutReplacesDoubleSpace() {
        let typing = TypingSessionController()
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        for character in ["h", "e", "l", "l", "o"] {
            apply(typing, typing.handleKey(character))
        }
        let first = typing.handleSpace()
        XCTAssertTrue(first.text.hasSuffix(" "), "first Space should insert a space")
        apply(typing, first)

        let second = typing.handleSpace()
        XCTAssertEqual(second, .replace(deleteCount: 1, with: ". "))
        apply(typing, second)
        XCTAssertTrue(typing.shiftActive, "period+space must arm sentence Shift")
    }

    @MainActor
    func testPeriodShortcutDoesNotFireAfterAnotherLetter() {
        let typing = TypingSessionController()
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        apply(typing, typing.handleKey("h"))
        apply(typing, typing.handleSpace())
        apply(typing, typing.handleKey("i"))
        let second = typing.handleSpace()
        XCTAssertEqual(second, .insert(" "))
    }

    @MainActor
    func testPeriodShortcutDoesNotFireAfterSentenceTerminator() {
        let typing = TypingSessionController()
        _ = typing.setLanguage(.english)
        typing.precedingTextProvider = { "Hello." }
        typing.enterTypingMode()
        typing.syncAutocapitalization()

        apply(typing, typing.handleSpace())
        let second = typing.handleSpace()
        XCTAssertEqual(second, .insert(" "))
    }

    @MainActor
    func testChineseSpaceDoesNotUsePeriodShortcut() {
        let typing = TypingSessionController()
        _ = typing.setLanguage(.chinese)
        let first = typing.handleSpace()
        let second = typing.handleSpace()
        XCTAssertEqual(first.text, " ")
        XCTAssertEqual(second.text, " ")
        XCTAssertEqual(second.deleteCount, 0)
    }

    func testPeriodShortcutPredicate() {
        XCTAssertTrue(PeriodShortcut.shouldReplacePreviousSpace(precedingText: "hello "))
        XCTAssertTrue(PeriodShortcut.shouldReplacePreviousSpace(precedingText: "你 "))
        XCTAssertTrue(PeriodShortcut.shouldReplacePreviousSpace(precedingText: "v2 "))
        XCTAssertFalse(PeriodShortcut.shouldReplacePreviousSpace(precedingText: "hello. "))
        XCTAssertFalse(PeriodShortcut.shouldReplacePreviousSpace(precedingText: "hello  "))
        XCTAssertFalse(PeriodShortcut.shouldReplacePreviousSpace(precedingText: "hello"))
        XCTAssertFalse(PeriodShortcut.shouldReplacePreviousSpace(precedingText: " "))
        XCTAssertTrue(PeriodShortcut.shouldArm(afterSpaceFollowing: "hello"))
        XCTAssertFalse(PeriodShortcut.shouldArm(afterSpaceFollowing: "hello."))
        XCTAssertFalse(PeriodShortcut.shouldArm(afterSpaceFollowing: "hello "))
    }

    func testLearningStoreClearRemovesBoosts() {
        let suiteName = "EnglishLearningStore.clear.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = EnglishLearningStore(defaults: defaults)
        store.recordAcceptance(of: "hello")
        XCTAssertGreaterThan(store.boost(for: "hello"), 0)
        store.clear()
        XCTAssertEqual(store.boost(for: "hello"), 0)
        XCTAssertTrue(store.snapshot().isEmpty)
    }

    @MainActor
    func testEnglishQuickTypePutsVerbatimFirstAndMarksCorrection() {
        let typing = makeIsolatedEnglishSession(suite: "english.quicktype.bar.test")

        for character in ["t", "e", "h"] {
            _ = typing.handleKey(character)
        }
        XCTAssertEqual(typing.composition.candidates.first?.role, .verbatim)
        XCTAssertEqual(
            typing.composition.candidates.first?.text.lowercased(),
            "teh"
        )
        XCTAssertTrue(
            typing.composition.candidates.contains {
                $0.role == .correction && $0.text.lowercased() == "the"
            }
        )
        XCTAssertLessThanOrEqual(typing.composition.candidates.count, EnglishSuggestionEngine.slotCount)
    }

    @MainActor
    func testEnglishSpaceAppliesCorrectionSlotOnly() {
        let typing = makeIsolatedEnglishSession(suite: "english.quicktype.space.test")

        for character in ["t", "e", "h"] {
            _ = typing.handleKey(character)
        }
        let spaced = typing.handleSpace()
        XCTAssertEqual(spaced.deleteCount, 3)
        XCTAssertTrue(spaced.text.lowercased().hasPrefix("the"))
        XCTAssertTrue(typing.composition.candidates.isEmpty)
    }

    @MainActor
    func testEnglishSpaceKeepsVerbatimWhenNoCorrection() {
        let typing = makeIsolatedEnglishSession(suite: "english.quicktype.verbatim.test")

        for character in ["h", "e", "l"] {
            _ = typing.handleKey(character)
        }
        let spaced = typing.handleSpace()
        XCTAssertEqual(spaced, .insert(" "))
        XCTAssertTrue(typing.composition.candidates.isEmpty)
    }

    func testTitleCaseNamesAreNotAutocorrected() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertNil(engine.correctionDecision(for: "Rocky", personalTerms: [], learnedBoosts: [:]))
        XCTAssertNil(engine.correctionDecision(for: "Wang", personalTerms: [], learnedBoosts: [:]))
        XCTAssertNil(engine.correctionDecision(for: "Chen", personalTerms: [], learnedBoosts: [:]))
        XCTAssertNil(engine.correctionDecision(for: "Li", personalTerms: [], learnedBoosts: [:]))
    }

    func testTitleCaseTranspositionStillCorrects() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertEqual(
            engine.correctionDecision(for: "Teh", personalTerms: [], learnedBoosts: [:])?.replacement,
            "The"
        )
    }

    func testProximityCorrectsAdjacentKeyTypos() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertEqual(
            engine.correctionDecision(for: "gppd", personalTerms: [], learnedBoosts: [:])?.replacement,
            "good"
        )
    }

    func testRealWordFormIsNotCorrectedToFrom() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertNil(engine.correctionDecision(for: "form", personalTerms: [], learnedBoosts: [:]))
    }

    func testSupplementaryLexiconBlocksAutocorrect() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertNil(
            engine.correctionDecision(
                for: "teh",
                personalTerms: [],
                learnedBoosts: [:],
                systemWords: ["teh"]
            )
        )
    }

    func testLearnedDefenseBlocksAutocorrect() {
        let engine = EnglishSuggestionEngine()
        engine.prepare()
        XCTAssertNil(
            engine.correctionDecision(
                for: "teh",
                personalTerms: [],
                learnedBoosts: ["teh": 5]
            )
        )
    }

    @MainActor
    func testAutocorrectDoesNotBoostReplacement() {
        let suite = "english.learning.polarity.test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = EnglishLearningStore(defaults: defaults)
        let typing = TypingSessionController(learningStore: store)
        typing.suggestionsEnabled = true
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        for character in ["t", "e", "h"] {
            _ = typing.handleKey(character)
        }
        _ = typing.handleSpace()
        XCTAssertEqual(store.boost(for: "the"), 0)
        XCTAssertEqual(store.boost(for: "teh"), 0)
    }

    @MainActor
    func testRejectingAutocorrectLearnsOriginal() {
        let suite = "english.learning.defense.test"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = EnglishLearningStore(defaults: defaults)
        let typing = TypingSessionController(learningStore: store)
        typing.suggestionsEnabled = true
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()

        for character in ["t", "e", "h"] {
            _ = typing.handleKey(character)
        }
        let spaced = typing.handleSpace()
        if spaced.deleteCount > 0 {
            _ = typing.handleKey("⌫")
            XCTAssertGreaterThanOrEqual(store.boost(for: "teh"), 5)
        }
    }

    func testQWERTYNeighborsIncludeDiagonals() {
        let aroundG = EnglishQWERTYProximity.neighbors(of: "g", includingSelf: true)
        XCTAssertTrue(aroundG.contains("t"))
        XCTAssertTrue(aroundG.contains("f"))
        XCTAssertTrue(aroundG.contains("h"))
        XCTAssertTrue(aroundG.contains("b"))
        XCTAssertFalse(aroundG.contains("q"))
    }

    func testBigramsPredictNextWords() {
        let lexicon = EnglishLexicon()
        lexicon.prepare()
        let next = lexicon.nextWords(after: "thank", limit: 4)
        XCTAssertTrue(next.contains("you"))
    }

    @MainActor
    private func makeIsolatedEnglishSession(suite: String) -> TypingSessionController {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = EnglishLearningStore(defaults: defaults)
        let typing = TypingSessionController(learningStore: store)
        typing.suggestionsEnabled = true
        _ = typing.setLanguage(.english)
        typing.enterTypingMode()
        return typing
    }

    @MainActor
    private func apply(_ typing: TypingSessionController, _ output: TypingOutput) {
        typing.syncAutocapitalization(
            accountingForInsert: output.text,
            deleteCount: output.deleteCount
        )
    }
}
