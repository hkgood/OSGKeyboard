// TypingSessionController.swift
// OSGKeyboard · Shared
//
// Owns the typing-surface engine + layout provider. Injected into the
// keyboard extension; torn down when leaving typing mode.

import Foundation
import Combine

@MainActor
public final class TypingSessionController: ObservableObject {
    @Published public private(set) var language: TypingInputLanguage = .chinese
    @Published public private(set) var page: TypingKeyPage = .letters
    @Published public private(set) var shiftActive: Bool = false
    @Published public private(set) var capsLock: Bool = false
    @Published public private(set) var composition: TypingComposition = .empty
    @Published public private(set) var engineReady: Bool = false
    @Published public private(set) var schema: TypingInputSchema
    /// Chinese-only: key grid replaced by a same-height candidate grid.
    @Published public private(set) var isCandidatePanelExpanded: Bool = false
    @Published public var lastError: String?

    /// When true, English suggestions / autocorrect stay off (secure fields).
    @Published public var suggestionsEnabled: Bool = true

    /// Chevron appears only for Chinese composition with at least two candidates.
    public var canExpandCandidatePanel: Bool {
        language == .chinese && composition.candidates.count >= 2
    }

    /// Live document prefix ahead of the caret (from `UITextDocumentProxy`).
    public var precedingTextProvider: (() -> String?)?
    /// Host field autocapitalization preference.
    public var autocapitalizationModeProvider: (() -> TypingAutocapitalizationMode)?

    public let layout: TypingLayoutProviding
    private let engine: RimeEngineBridging
    private let englishEngine: EnglishSuggestionEngine
    private let learningStore: EnglishLearningStore
    private var prepared = false

    // English word-level state (characters are already in the document).
    private var englishCurrentWord: String = ""
    private var englishPreviousWord: String = ""
    private var pendingAutocorrection: EnglishCorrectionDecision?
    private var personalTermsCache: [String] = []

    public init(
        engine: RimeEngineBridging = LibrimeEngine(),
        layout: TypingLayoutProviding = StandardTypingLayout(),
        englishEngine: EnglishSuggestionEngine = EnglishSuggestionEngine(),
        learningStore: EnglishLearningStore = EnglishLearningStore()
    ) {
        self.engine = engine
        self.layout = layout
        self.englishEngine = englishEngine
        self.learningStore = learningStore
        schema = engine.schema
    }

    public var keyRows: [[String]] {
        var rows = layout.rows(for: page, shiftActive: shiftActive || capsLock)
        if page == .letters,
           language == .chinese,
           schema != .fullPinyin,
           rows.indices.contains(2),
           rows[2].first == "⇧" {
            // Microsoft/Sogou use semicolon for "ing"; Chinese composition
            // does not need Shift, so keep the standard row width stable.
            rows[2][0] = ";"
        }
        return rows
    }

    public func enterTypingMode() {
        TypingInputConfiguration.shared.reload()
        refreshPersonalTerms()
        englishEngine.prepare()
        syncAutocapitalization()
        Task { await prepareIfNeeded() }
    }

    public func leaveTypingMode() {
        engine.teardown()
        prepared = false
        engineReady = false
        composition = .empty
        isCandidatePanelExpanded = false
        page = .letters
        shiftActive = false
        capsLock = false
        clearEnglishWordState(keepPrevious: false)
    }

    public func toggleCandidatePanelExpanded() {
        guard canExpandCandidatePanel else {
            isCandidatePanelExpanded = false
            return
        }
        isCandidatePanelExpanded.toggle()
    }

    public func collapseCandidatePanel() {
        isCandidatePanelExpanded = false
    }

    public func toggleLanguage() -> TypingOutput {
        let next: TypingInputLanguage = language == .chinese ? .english : .chinese
        return setLanguage(next)
    }

    /// Selects a specific language for the shared voice / Chinese / English
    /// capsule. Chinese preedit is flushed; English half-words are already
    /// in the document so we only clear suggestion state.
    public func setLanguage(_ newLanguage: TypingInputLanguage) -> TypingOutput {
        guard language != newLanguage else { return .none }
        var output = TypingOutput.none
        if language == .chinese, !composition.preedit.isEmpty {
            let raw = engine.flushPreedit()
            if !raw.isEmpty { output = .insert(raw) }
        }
        language = newLanguage
        engine.setLanguage(newLanguage)
        page = .letters
        isCandidatePanelExpanded = false
        if newLanguage == .english {
            clearEnglishWordState(keepPrevious: false)
            refreshPersonalTerms()
            englishEngine.prepare()
            refreshEnglishSuggestions()
            syncAutocapitalization()
        } else {
            clearEnglishWordState(keepPrevious: false)
            composition = engine.composition
        }
        return output
    }

    /// Flushes raw preedit, selects the next built-in scheme, and returns the
    /// text that the caller should insert before switching.
    public func cycleSchema() -> TypingOutput {
        let raw = composition.preedit.isEmpty ? "" : engine.flushPreedit()
        let schemas = TypingInputSchema.allCases
        let current = schemas.firstIndex(of: schema) ?? 0
        let next = schemas[(current + 1) % schemas.count]
        if engine.setSchema(next) {
            schema = next
            TypingInputConfiguration.shared.schema = next
        }
        composition = engine.composition
        syncCandidatePanelVisibility()
        return raw.isEmpty ? .none : .insert(raw)
    }

    public func setPage(_ page: TypingKeyPage) {
        self.page = page
        shiftActive = false
        if page == .letters {
            syncAutocapitalization()
        }
    }

    /// Handle a visible key label.
    public func handleKey(_ label: String) -> TypingOutput {
        switch label {
        case "⇧":
            if shiftActive {
                capsLock = true
                shiftActive = false
            } else if capsLock {
                capsLock = false
            } else {
                shiftActive = true
            }
            return .none
        case "⌫":
            return handleBackspace()
        case "123":
            setPage(.numbers)
            return .none
        case "#+=":
            setPage(.symbols)
            return .none
        case "ABC", "abc":
            setPage(.letters)
            return .none
        default:
            break
        }

        if page != .letters {
            let out = commitEnglishWordIfNeededBeforeNonLetter()
            if !capsLock { shiftActive = false }
            if out.isEmpty {
                return .insert(label)
            }
            return TypingOutput(deleteCount: out.deleteCount, text: out.text + label)
        }

        guard let ch = label.first else { return .none }

        if language == .english {
            return handleEnglishCharacter(ch)
        }

        // Chinese letters → compose
        let committed = engine.processCharacter(ch) ?? ""
        composition = engine.composition
        syncCandidatePanelVisibility()
        if !capsLock { shiftActive = false }
        return committed.isEmpty ? .none : .insert(committed)
    }

    public func handleSpace() -> TypingOutput {
        if language == .english {
            return commitEnglishWord(suffix: " ")
        }
        let text = engine.processSpace() ?? " "
        composition = engine.composition
        syncCandidatePanelVisibility()
        return .insert(text)
    }

    public func handleReturn() -> TypingOutput {
        if language == .english {
            return commitEnglishWord(suffix: "\n")
        }
        let text = engine.processReturn() ?? "\n"
        composition = engine.composition
        syncCandidatePanelVisibility()
        return .insert(text)
    }

    public func selectCandidate(at index: Int) -> TypingOutput {
        if language == .english {
            return selectEnglishCandidate(at: index)
        }
        guard composition.candidates.indices.contains(index) else { return .none }
        // Display order may put phrases before first-syllable chars; select by engine index.
        let engineIndex = composition.candidates[index].engineIndex
        let text = engine.selectCandidate(at: engineIndex)
        composition = engine.composition
        // Selecting always collapses; follow-up composition may reopen ▼.
        isCandidatePanelExpanded = false
        syncCandidatePanelVisibility()
        return text.isEmpty ? .none : .insert(text)
    }

    // MARK: - English

    private func handleEnglishCharacter(_ ch: Character) -> TypingOutput {
        pendingAutocorrection = nil
        if ch.isLetter {
            englishCurrentWord.append(ch)
            if !capsLock { shiftActive = false }
            refreshEnglishSuggestions()
            return .insert(String(ch))
        }

        // Punctuation / digit: commit current word first, then insert.
        var output = commitEnglishWord(suffix: "")
        if !capsLock { shiftActive = false }
        if output.isEmpty {
            return .insert(String(ch))
        }
        return TypingOutput(deleteCount: output.deleteCount, text: output.text + String(ch))
    }

    private func handleBackspace() -> TypingOutput {
        if language == .chinese, !engine.composition.preedit.isEmpty {
            let committed = engine.processBackspace() ?? ""
            composition = engine.composition
            syncCandidatePanelVisibility()
            return committed.isEmpty ? .none : .insert(committed)
        }

        if language == .english {
            if let pending = pendingAutocorrection {
                // Undo last autocorrection: delete replacement+suffix, restore original.
                let deleteCount = pending.undoDeleteCount
                pendingAutocorrection = nil
                englishCurrentWord = pending.original
                learningStore.recordDefense(of: pending.original)
                refreshEnglishSuggestions()
                return .replace(deleteCount: deleteCount, with: pending.original)
            }
            if !englishCurrentWord.isEmpty {
                englishCurrentWord.removeLast()
                refreshEnglishSuggestions()
            } else if !englishPreviousWord.isEmpty {
                // Stepping back into the previous word.
                englishCurrentWord = englishPreviousWord
                englishPreviousWord = ""
                refreshEnglishSuggestions()
            } else {
                composition = .empty
            }
        }
        return .backspace
    }

    private func commitEnglishWord(suffix: String) -> TypingOutput {
        let word = englishCurrentWord
        defer {
            if !capsLock { shiftActive = false }
        }

        guard suggestionsEnabled, !word.isEmpty else {
            if !word.isEmpty {
                englishPreviousWord = word
                englishCurrentWord = ""
            }
            refreshEnglishSuggestions(afterCommittedWord: word.isEmpty ? nil : word)
            return suffix.isEmpty ? .none : .insert(suffix)
        }

        if var decision = englishEngine.correctionDecision(
            for: word,
            personalTerms: personalTermsCache,
            learnedBoosts: learningStore.snapshot()
        ) {
            decision.appliedSuffix = suffix
            pendingAutocorrection = decision
            englishPreviousWord = decision.replacement
            englishCurrentWord = ""
            learningStore.recordAcceptance(of: decision.replacement)
            // Suggestions stay hidden until the user starts the next word.
            composition = .empty
            return .replace(
                deleteCount: word.count,
                with: decision.replacement + suffix
            )
        }

        englishPreviousWord = word
        englishCurrentWord = ""
        pendingAutocorrection = nil
        learningStore.recordAcceptance(of: word, amount: 1)
        refreshEnglishSuggestions(afterCommittedWord: word)
        return suffix.isEmpty ? .none : .insert(suffix)
    }

    private func selectEnglishCandidate(at index: Int) -> TypingOutput {
        guard composition.candidates.indices.contains(index) else { return .none }
        let chosen = composition.candidates[index].text

        // Restoring original after autocorrect (no current word).
        if englishCurrentWord.isEmpty,
           let pending = pendingAutocorrection,
           chosen.compare(pending.original, options: [.caseInsensitive]) == .orderedSame {
            let deleteCount = pending.undoDeleteCount
            pendingAutocorrection = nil
            englishPreviousWord = pending.original
            englishCurrentWord = ""
            learningStore.recordDefense(of: pending.original)
            refreshEnglishSuggestions(afterCommittedWord: pending.original)
            return .replace(deleteCount: deleteCount, with: pending.original + " ")
        }

        if !englishCurrentWord.isEmpty {
            let deleteCount = englishCurrentWord.count
            englishPreviousWord = chosen
            englishCurrentWord = ""
            pendingAutocorrection = nil
            learningStore.recordAcceptance(of: chosen)
            refreshEnglishSuggestions(afterCommittedWord: chosen)
            return .replace(deleteCount: deleteCount, with: chosen + " ")
        }

        // Next-word prediction tap.
        englishPreviousWord = chosen
        englishCurrentWord = ""
        pendingAutocorrection = nil
        learningStore.recordAcceptance(of: chosen)
        refreshEnglishSuggestions(afterCommittedWord: chosen)
        return .insert(chosen + " ")
    }

    private func commitEnglishWordIfNeededBeforeNonLetter() -> TypingOutput {
        guard language == .english, !englishCurrentWord.isEmpty else { return .none }
        return commitEnglishWord(suffix: "")
    }

    private func refreshEnglishSuggestions(afterCommittedWord word: String? = nil) {
        guard language == .english else { return }
        guard suggestionsEnabled else {
            composition = .empty
            return
        }
        // Idle / between words: no candidate bar. Completions start after
        // the first letter of the current word.
        guard !englishCurrentWord.isEmpty else {
            composition = .empty
            return
        }
        let previous = word ?? englishPreviousWord
        let context = EnglishSuggestionContext(
            currentWord: englishCurrentWord,
            previousWord: previous,
            personalTerms: personalTermsCache,
            learnedBoosts: learningStore.snapshot(),
            includeOriginalAfterCorrection: nil
        )
        composition = englishEngine.compositionWhileTyping(context)
    }

    /// Arms Shift for sentence / word starts using the host field traits.
    public func syncAutocapitalization() {
        guard language == .english, page == .letters else { return }
        guard !capsLock else { return }
        let mode = autocapitalizationModeProvider?() ?? .sentences
        let preceding = precedingTextProvider?()
        shiftActive = TypingAutocapitalization.shouldCapitalize(
            precedingText: preceding,
            mode: mode
        )
    }

    private func clearEnglishWordState(keepPrevious: Bool) {
        englishCurrentWord = ""
        if !keepPrevious { englishPreviousWord = "" }
        pendingAutocorrection = nil
    }

    private func refreshPersonalTerms() {
        // English keyboard only accepts Latin hotwords; Chinese terms stay for ASR/polish.
        personalTermsCache = AppGroupStore().personalDictionary.englishTypingHotwords()
    }

    /// Collapse the expand panel when Chinese no longer has enough candidates.
    private func syncCandidatePanelVisibility() {
        if !canExpandCandidatePanel {
            isCandidatePanelExpanded = false
        }
    }

    private func prepareIfNeeded() async {
        guard !prepared else { return }
        do {
            try await engine.prepare()
            engine.setLanguage(language)
            prepared = true
            engineReady = engine.isReady
            schema = engine.schema
            lastError = nil
            if language == .english {
                refreshEnglishSuggestions()
            }
        } catch {
            lastError = error.localizedDescription
            engineReady = false
        }
    }
}
