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
    /// Finger is down on Shift (iOS: hold for continuous uppercase; release ends).
    @Published public private(set) var shiftHeld: Bool = false
    @Published public private(set) var composition: TypingComposition = .empty
    @Published public private(set) var engineReady: Bool = false
    @Published public private(set) var schema: TypingInputSchema
    /// Chinese-only: key grid replaced by a same-height candidate grid.
    @Published public private(set) var isCandidatePanelExpanded: Bool = false
    @Published public var lastError: String?
    /// `true` when `lastError` can only be cleared by deploying resources in
    /// the host app — drives the keyboard's tappable setup affordance.
    @Published public private(set) var lastErrorNeedsHostDeployment: Bool = false

    /// When true, English suggestions / autocorrect stay off (secure fields).
    /// Chinese composition is also skipped so passwords never enter Rime userdb.
    @Published public var suggestionsEnabled: Bool = true {
        didSet {
            guard oldValue, !suggestionsEnabled else { return }
            abandonChineseComposition()
        }
    }
    /// `UITextChecker` completions / guesses. Empty in unit tests.
    public var systemLexicon: EnglishSystemLexiconProviding = EmptyEnglishSystemLexicon()
    /// Names and text replacements from `requestSupplementaryLexicon`.
    public var supplementaryWords: [String] = []

    /// Chevron appears only for Chinese composition with at least two candidates.
    public var canExpandCandidatePanel: Bool {
        language == .chinese && composition.candidates.count >= 2
    }

    /// Live document prefix ahead of the caret (from `UITextDocumentProxy`).
    public var precedingTextProvider: (() -> String?)?
    /// Live document suffix after the caret. A non-empty word suffix means
    /// the caret is inside a word, where backward-only replacement is unsafe.
    public var followingTextProvider: (() -> String?)?
    /// Host field autocapitalization preference.
    public var autocapitalizationModeProvider: (() -> TypingAutocapitalizationMode)?

    public let layout: TypingLayoutProviding
    private let engineFactory: @MainActor () -> RimeEngineBridging
    private let englishFactory: @MainActor () -> EnglishSuggestionEngine
    private let learningStore: EnglishLearningStore
    private var engineStorage: RimeEngineBridging?
    private var englishStorage: EnglishSuggestionEngine?
    private var prepared = false
    private var prepareTask: Task<Void, Never>?

    private var engine: RimeEngineBridging {
        if let engineStorage { return engineStorage }
        let created = engineFactory()
        engineStorage = created
        schema = created.schema
        return created
    }

    private var englishEngine: EnglishSuggestionEngine {
        if let englishStorage { return englishStorage }
        let created = englishFactory()
        englishStorage = created
        return created
    }

    // English word-level state (characters are already in the document).
    private var englishCurrentWord: String = ""
    private var englishPreviousWord: String = ""
    private var englishFollowingWordSuffix: String = ""
    private var pendingAutocorrection: EnglishCorrectionDecision?
    private var personalTermsCache: [String] = []
    /// User tapped Shift for a one-shot capital; autocap must not overwrite this.
    private var shiftPrimedByUser = false
    /// True if any key was typed while the current Shift hold was active.
    private var typedWhileShiftHeld = false
    /// Local caret-prefix mirror so autocap survives stale `documentContextBeforeInput`
    /// (common in Notes). Capped; reseeds from the proxy when it looks fresh.
    private var precedingShadow = ""
    private static let precedingShadowLimit = 400
    /// iOS "." Shortcut: second Space shortly after a Space that followed a word.
    private var periodShortcutArmed = false
    private var lastSpaceAt: Date?

    public init(
        engine: (@MainActor () -> RimeEngineBridging)? = nil,
        layout: TypingLayoutProviding = StandardTypingLayout(),
        englishEngine: (@MainActor () -> EnglishSuggestionEngine)? = nil,
        learningStore: EnglishLearningStore = EnglishLearningStore()
    ) {
        self.engineFactory = engine ?? { LibrimeEngine() }
        self.layout = layout
        self.englishFactory = englishEngine ?? { EnglishSuggestionEngine() }
        self.learningStore = learningStore
        // Avoid constructing librime until the first Chinese keystroke / prepare.
        schema = TypingInputConfiguration.shared.schema
    }

    /// Letter keys and Shift glyph follow any armed / held / Caps Lock state.
    public var isShiftEnabled: Bool {
        shiftActive || capsLock || shiftHeld
    }

    public var keyRows: [[String]] {
        var rows = layout.rows(
            for: page,
            language: language,
            shiftActive: isShiftEnabled
        )
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
        let hostHeavy = FlowSessionBridge.isHostHeavy()
        KeyboardExtensionMemoryTelemetry.record(
            "typing.enter.begin",
            details: "language=\(language.rawValue) schema=\(schema.rawValue) "
                + "hostHeavy=\(hostHeavy ? 1 : 0)"
        )
        OSGDiag.log(
            "typing.enter begin lang=\(language.rawValue) schema=\(schema.rawValue) "
                + "hostHeavy=\(hostHeavy ? 1 : 0) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        TypingInputConfiguration.shared.reload()
        refreshPersonalTerms()
        // mmap the English table only while English is active. Chinese typing
        // already has Rime; loading both on appear is what jetsams the extension.
        if language == .english {
            englishEngine.prepare()
            KeyboardExtensionMemoryTelemetry.record(
                "typing.englishPrepare.done",
                details: "language=\(language.rawValue)"
            )
            OSGDiag.log("typing.enter after englishPrepare \(OSGDiag.memoryTag())", category: "boot")
        } else {
            EnglishLexicon.shared.unload()
            KeyboardExtensionMemoryTelemetry.record(
                "typing.englishPrepare.skipped",
                details: "language=\(language.rawValue)"
            )
            OSGDiag.log("typing.enter skip englishPrepare lang=\(language.rawValue) \(OSGDiag.memoryTag())", category: "boot")
        }
        syncAutocapitalization()
        if hostHeavy {
            KeyboardExtensionMemoryTelemetry.record(
                "typing.rimePrepare.deferred",
                details: "hostHeavy=1"
            )
            OSGDiag.log("typing.enter defer rime hostHeavy=1 — retry scheduled", category: "boot")
            prepareTask?.cancel()
            prepareTask = Task { [weak self] in
                for _ in 0..<40 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if !FlowSessionBridge.isHostHeavy() {
                        await self.prepareIfNeeded()
                        self.prepareTask = nil
                        return
                    }
                }
                self?.prepareTask = nil
            }
            return
        }
        if prepareTask == nil, !prepared {
            prepareTask = Task { [weak self] in
                await self?.prepareIfNeeded()
                self?.prepareTask = nil
            }
        }
    }

    public func leaveTypingMode() {
        KeyboardExtensionMemoryTelemetry.record(
            "typing.leave.begin",
            details: "language=\(language.rawValue)"
        )
        OSGDiag.log("typing.leave \(OSGDiag.memoryTag())", category: "boot")
        prepareTask?.cancel()
        prepareTask = nil
        engineStorage?.teardown()
        prepared = false
        engineReady = false
        composition = .empty
        isCandidatePanelExpanded = false
        page = .letters
        resetShiftState()
        clearEnglishWordState(keepPrevious: false)
        clearPeriodShortcut()
        // Drop English lexicon pages when leaving typing (jetsam recovery).
        EnglishLexicon.shared.unload()
        englishStorage = nil
        KeyboardExtensionMemoryTelemetry.record(
            "typing.leave.done",
            details: "language=\(language.rawValue)"
        )
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
        clearPeriodShortcut()
        if newLanguage == .english {
            clearEnglishWordState(keepPrevious: false)
            refreshPersonalTerms()
            englishEngine.prepare()
            refreshEnglishSuggestions()
            syncAutocapitalization()
            synchronizeEnglishDocumentContext(caretMoved: true)
        } else {
            clearEnglishWordState(keepPrevious: false)
            EnglishLexicon.shared.unload()
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
        resetShiftState()
        clearPeriodShortcut()
        if page == .letters {
            syncAutocapitalization()
        }
    }

    /// Touch-down on Shift: hold for continuous uppercase (release ends hold).
    public func beginShiftHold() {
        guard page == .letters else { return }
        shiftHeld = true
        typedWhileShiftHeld = false
    }

    /// Touch-up on Shift: end hold; if nothing was typed, treat as a tap.
    public func endShiftHold() {
        guard shiftHeld else { return }
        let typed = typedWhileShiftHeld
        shiftHeld = false
        typedWhileShiftHeld = false
        if typed {
            if !capsLock && !shiftPrimedByUser {
                syncAutocapitalization()
            }
            return
        }
        handleShiftTap()
    }

    /// Handle a visible key label.
    public func handleKey(_ label: String) -> TypingOutput {
        clearPeriodShortcut()
        switch label {
        case "⇧":
            // Tests / non-gesture callers: same as a completed Shift tap.
            handleShiftTap()
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
            clearOneShotShiftIfNeeded()
            if out.isEmpty {
                return .insert(label)
            }
            return TypingOutput(deleteCount: out.deleteCount, text: out.text + label)
        }

        guard let ch = label.first else { return .none }

        if language == .english {
            return handleEnglishCharacter(ch)
        }

        if !suggestionsEnabled {
            clearOneShotShiftIfNeeded()
            abandonChineseComposition()
            return .insert(String(ch))
        }

        // Chinese + Shift: insert Latin directly (iOS-style mix-in), leave Rime
        // composition untouched. Rime's alphabet is lowercase-only, so uppercase
        // keycodes would otherwise be rejected with no output.
        if isShiftEnabled, ch.isLetter {
            clearOneShotShiftIfNeeded()
            return .insert(String(ch))
        }

        // Chinese letters → compose
        let committed = engine.processCharacter(ch) ?? ""
        composition = engine.composition
        syncCandidatePanelVisibility()
        clearOneShotShiftIfNeeded()
        return committed.isEmpty ? .none : .insert(committed)
    }

    public func handleSpace() -> TypingOutput {
        if language == .english {
            return handleEnglishSpace()
        }
        clearPeriodShortcut()
        if !suggestionsEnabled {
            abandonChineseComposition()
            return .insert(" ")
        }
        let text = engine.processSpace() ?? " "
        composition = engine.composition
        syncCandidatePanelVisibility()
        return .insert(text)
    }

    public func handleReturn() -> TypingOutput {
        clearPeriodShortcut()
        if language == .english {
            return commitEnglishWord(suffix: "\n")
        }
        if !suggestionsEnabled {
            abandonChineseComposition()
            return .insert("\n")
        }
        let text = engine.processReturn() ?? "\n"
        composition = engine.composition
        syncCandidatePanelVisibility()
        return .insert(text)
    }

    public func selectCandidate(at index: Int) -> TypingOutput {
        clearPeriodShortcut()
        if language == .english {
            return selectEnglishCandidate(at: index)
        }
        if !suggestionsEnabled {
            return .none
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

    /// Drop in-flight pinyin so secure fields cannot commit into userdb.
    private func abandonChineseComposition() {
        engineStorage?.clearComposition()
        composition = .empty
        isCandidatePanelExpanded = false
    }

    // MARK: - English

    private func handleEnglishSpace() -> TypingOutput {
        let preceding = precedingTextForShortcut()
        if periodShortcutArmed,
           let stamped = lastSpaceAt,
           Date().timeIntervalSince(stamped) <= PeriodShortcut.doubleTapInterval,
           PeriodShortcut.shouldReplacePreviousSpace(precedingText: preceding) {
            clearPeriodShortcut()
            let wordOut = commitEnglishWord(suffix: "")
            let deleteCount = wordOut.deleteCount + 1
            return TypingOutput(deleteCount: deleteCount, text: wordOut.text + ". ")
        }

        let output = commitEnglishWord(suffix: " ")
        if PeriodShortcut.shouldArm(afterSpaceFollowing: preceding) {
            periodShortcutArmed = true
            lastSpaceAt = Date()
        } else {
            clearPeriodShortcut()
        }
        return output
    }

    private func precedingTextForShortcut() -> String {
        if !precedingShadow.isEmpty { return precedingShadow }
        return precedingTextProvider?() ?? ""
    }

    private func clearPeriodShortcut() {
        periodShortcutArmed = false
        lastSpaceAt = nil
    }

    private func handleEnglishCharacter(_ ch: Character) -> TypingOutput {
        pendingAutocorrection = nil
        if ch.isLetter {
            englishCurrentWord.append(ch)
            clearOneShotShiftIfNeeded()
            refreshEnglishSuggestions()
            return .insert(String(ch))
        }

        // Punctuation / digit: commit current word first, then insert.
        let output = commitEnglishWord(suffix: "")
        clearOneShotShiftIfNeeded()
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
                #if canImport(UIKit)
                UIKitEnglishSystemLexicon.learnWord(pending.original)
                #endif
                refreshEnglishSuggestions()
                return .replace(deleteCount: deleteCount, with: pending.original)
            }
            if !englishCurrentWord.isEmpty {
                englishCurrentWord.removeLast()
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
            clearOneShotShiftIfNeeded()
        }

        guard suggestionsEnabled,
              englishFollowingWordSuffix.isEmpty,
              !word.isEmpty else {
            if !word.isEmpty {
                englishPreviousWord = word
                englishCurrentWord = ""
            }
            refreshEnglishSuggestions(afterCommittedWord: word.isEmpty ? nil : word)
            return suffix.isEmpty ? .none : .insert(suffix)
        }

        if englishCurrentWordMatchesDocument(),
           var decision = englishEngine.correctionDecision(
            for: word,
            personalTerms: personalTermsCache,
            learnedBoosts: learningStore.snapshot(),
            previousWord: englishPreviousWord,
            systemWords: supplementaryWords,
            systemGuesses: systemLexicon.guesses(for: word, limit: 6)
        ) {
            decision.appliedSuffix = suffix
            pendingAutocorrection = decision
            englishPreviousWord = decision.replacement
            englishCurrentWord = ""
            // Machine-applied correction does not count as the user accepting
            // the replacement — otherwise names train the wrong word.
            refreshEnglishSuggestions(afterCommittedWord: decision.replacement)
            return .replace(
                deleteCount: word.count,
                with: decision.replacement + suffix
            )
        }

        englishPreviousWord = word
        englishCurrentWord = ""
        pendingAutocorrection = nil
        // Learn OOV / names the user actually committed; skip common words.
        if !englishEngine.isKnownWord(
            word,
            personalTerms: personalTermsCache,
            systemWords: supplementaryWords
        ) {
            learningStore.recordDefense(of: word, amount: 2)
            #if canImport(UIKit)
            UIKitEnglishSystemLexicon.learnWord(word)
            #endif
        }
        refreshEnglishSuggestions(afterCommittedWord: word)
        return suffix.isEmpty ? .none : .insert(suffix)
    }

    private func selectEnglishCandidate(at index: Int) -> TypingOutput {
        guard composition.candidates.indices.contains(index) else { return .none }
        guard englishCandidateAnchorMatchesDocument() else { return .none }
        let candidate = composition.candidates[index]
        let chosen = candidate.text

        // Restoring original after autocorrect (no current word).
        if englishCurrentWord.isEmpty,
           let pending = pendingAutocorrection,
           chosen.compare(pending.original, options: [.caseInsensitive]) == .orderedSame {
            let deleteCount = pending.undoDeleteCount
            pendingAutocorrection = nil
            englishPreviousWord = pending.original
            englishCurrentWord = ""
            learningStore.recordDefense(of: pending.original)
            #if canImport(UIKit)
            UIKitEnglishSystemLexicon.learnWord(pending.original)
            #endif
            refreshEnglishSuggestions(afterCommittedWord: pending.original)
            return .replace(deleteCount: deleteCount, with: pending.original + " ")
        }

        if candidate.role == .verbatim {
            learningStore.recordDefense(of: chosen)
            #if canImport(UIKit)
            UIKitEnglishSystemLexicon.learnWord(chosen)
            #endif
        } else {
            learningStore.recordAcceptance(of: chosen)
        }

        if !englishCurrentWord.isEmpty {
            let deleteCount = englishCurrentWord.count
            englishPreviousWord = chosen
            englishCurrentWord = ""
            pendingAutocorrection = nil
            refreshEnglishSuggestions(afterCommittedWord: chosen)
            return .replace(deleteCount: deleteCount, with: chosen + " ")
        }

        // Next-word prediction tap.
        englishPreviousWord = chosen
        englishCurrentWord = ""
        pendingAutocorrection = nil
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
            clearEnglishWordState(keepPrevious: false)
            composition = .empty
            return
        }
        guard englishFollowingWordSuffix.isEmpty else {
            composition = .empty
            return
        }
        // With no active English word, keep the candidate bar empty. This also
        // prevents next-word predictions from appearing between committed words.
        guard !englishCurrentWord.isEmpty else {
            composition = .empty
            return
        }
        let previous = word ?? englishPreviousWord
        let typed = englishCurrentWord
        let context = EnglishSuggestionContext(
            currentWord: typed,
            previousWord: previous,
            personalTerms: personalTermsCache,
            learnedBoosts: learningStore.snapshot(),
            includeOriginalAfterCorrection: pendingAutocorrection?.original,
            systemWords: supplementaryWords,
            systemCompletions: typed.isEmpty ? [] : systemLexicon.completions(prefix: typed, limit: 6),
            systemGuesses: typed.count >= 3 ? systemLexicon.guesses(for: typed, limit: 6) : []
        )
        composition = englishEngine.compositionWhileTyping(context)
    }

    /// Arms Shift for sentence / word starts using the host field traits.
    /// Manual one-shot, hold, and Caps Lock always win over autocapitalization.
    /// - Parameters:
    ///   - insert: Text just written through the document proxy (may not be
    ///     reflected in `documentContextBeforeInput` yet).
    ///   - deleteCount: Characters just deleted before `insert` (replace path).
    public func syncAutocapitalization(
        accountingForInsert insert: String = "",
        deleteCount: Int = 0
    ) {
        guard language == .english, page == .letters else { return }
        let preceding = resolvedPrecedingText(
            accountingForInsert: insert,
            deleteCount: deleteCount
        )
        if !insert.isEmpty || deleteCount > 0 {
            synchronizeEnglishWordState(
                precedingText: preceding ?? "",
                followingText: followingTextProvider?()
            )
        }
        guard !capsLock, !shiftHeld, !shiftPrimedByUser else { return }
        let mode = autocapitalizationModeProvider?() ?? .sentences
        shiftActive = TypingAutocapitalization.shouldCapitalize(
            precedingText: preceding,
            mode: mode
        )
    }

    /// Rebuilds English suggestion state from the real caret context.
    /// At the document end, callbacks keep the local shadow when a host
    /// briefly reports the immediately preceding edit (common in Notes).
    public func synchronizeEnglishDocumentContext(caretMoved: Bool = false) {
        guard language == .english else { return }
        if caretMoved {
            clearPeriodShortcut()
        }
        guard suggestionsEnabled else {
            clearEnglishWordState(keepPrevious: false)
            composition = .empty
            return
        }
        guard let preceding = precedingTextProvider?() else {
            if caretMoved {
                clearEnglishWordState(keepPrevious: false)
                composition = .empty
            }
            return
        }
        if shouldPreserveLocalEnglishContext(over: preceding) {
            return
        }
        applyEnglishDocumentSnapshot(preceding)
    }

    private func applyEnglishDocumentSnapshot(_ preceding: String) {
        if let pending = pendingAutocorrection,
           !preceding.hasSuffix(pending.replacement + pending.appliedSuffix) {
            pendingAutocorrection = nil
        }
        _ = storePrecedingShadow(preceding)
        synchronizeEnglishWordState(
            precedingText: preceding,
            followingText: followingTextProvider?()
        )
    }

    /// Prefer a fresh proxy; when the host lags (Notes), merge our just-applied edit.
    private func resolvedPrecedingText(
        accountingForInsert insert: String,
        deleteCount: Int
    ) -> String? {
        // Host-driven refresh (appear / textDidChange): reseed from proxy.
        if deleteCount == 0, insert.isEmpty {
            if let proxy = precedingTextProvider?() {
                return storePrecedingShadow(proxy)
            }
            return precedingShadow.isEmpty ? nil : precedingShadow
        }

        let proxy = precedingTextProvider?()

        if deleteCount > 0, !insert.isEmpty {
            if let proxy {
                if proxy.hasSuffix(insert) {
                    return storePrecedingShadow(proxy)
                }
                if proxy.count >= deleteCount {
                    return storePrecedingShadow(String(proxy.dropLast(deleteCount)) + insert)
                }
            }
            trimPrecedingShadow(by: deleteCount)
            return storePrecedingShadow(precedingShadow + insert)
        }

        if deleteCount > 0 {
            if let proxy, proxy.count + deleteCount == precedingShadow.count
                || (precedingShadow.count >= deleteCount
                    && String(precedingShadow.dropLast(deleteCount)) == proxy) {
                return storePrecedingShadow(proxy)
            }
            if precedingShadow.count >= deleteCount {
                return storePrecedingShadow(String(precedingShadow.dropLast(deleteCount)))
            }
            if let proxy { return storePrecedingShadow(proxy) }
            precedingShadow = ""
            return ""
        }

        // insert only
        if let proxy {
            if proxy.hasSuffix(insert) {
                return storePrecedingShadow(proxy)
            }
            return storePrecedingShadow(proxy + insert)
        }
        return storePrecedingShadow(precedingShadow + insert)
    }

    @discardableResult
    private func storePrecedingShadow(_ value: String) -> String {
        precedingShadow = String(value.suffix(Self.precedingShadowLimit))
        return precedingShadow
    }

    private func trimPrecedingShadow(by count: Int) {
        guard count > 0 else { return }
        if precedingShadow.count >= count {
            precedingShadow.removeLast(count)
        } else {
            precedingShadow = ""
        }
    }

    // MARK: - Shift

    /// Tap cycle: off → one-shot → Caps Lock → off (iOS-style second tap).
    private func handleShiftTap() {
        if capsLock {
            capsLock = false
            shiftActive = false
            shiftPrimedByUser = false
        } else if shiftActive {
            capsLock = true
            shiftActive = false
            shiftPrimedByUser = false
        } else {
            shiftActive = true
            shiftPrimedByUser = true
        }
    }

    /// After inserting a character: consume one-shot Shift, keep hold / Caps.
    private func clearOneShotShiftIfNeeded() {
        if shiftHeld {
            typedWhileShiftHeld = true
            return
        }
        guard !capsLock else { return }
        shiftActive = false
        shiftPrimedByUser = false
    }

    private func resetShiftState() {
        shiftActive = false
        capsLock = false
        shiftHeld = false
        shiftPrimedByUser = false
        typedWhileShiftHeld = false
        precedingShadow = ""
    }

    private func clearEnglishWordState(keepPrevious: Bool) {
        englishCurrentWord = ""
        if !keepPrevious { englishPreviousWord = "" }
        englishFollowingWordSuffix = ""
        pendingAutocorrection = nil
    }

    private func synchronizeEnglishWordState(
        precedingText: String,
        followingText: String?
    ) {
        let current = Self.englishWordBeforeCaret(in: precedingText)
        let textBeforeCurrent = String(precedingText.dropLast(current.count))
        englishCurrentWord = current
        englishPreviousWord = Self.previousEnglishWord(in: textBeforeCurrent)
        englishFollowingWordSuffix = Self.englishWordAfterCaret(in: followingText ?? "")
        refreshEnglishSuggestions()
    }

    private func shouldPreserveLocalEnglishContext(over proxyText: String) -> Bool {
        guard !englishCurrentWord.isEmpty,
              (followingTextProvider?() ?? "").isEmpty,
              !precedingShadow.isEmpty,
              proxyText != precedingShadow,
              Self.englishWordBeforeCaret(in: precedingShadow) == englishCurrentWord,
              Self.englishWordBeforeCaret(in: proxyText) != englishCurrentWord else {
            return false
        }
        return precedingShadow.hasPrefix(proxyText) || proxyText.hasPrefix(precedingShadow)
    }

    private func englishCandidateAnchorMatchesDocument() -> Bool {
        guard englishCurrentWordMatchesDocument() else {
            if let preceding = precedingTextProvider?() {
                applyEnglishDocumentSnapshot(preceding)
            } else {
                clearEnglishWordState(keepPrevious: false)
                composition = .empty
            }
            return false
        }
        return true
    }

    private func englishCurrentWordMatchesDocument() -> Bool {
        guard englishFollowingWordSuffix.isEmpty else { return false }
        if let following = followingTextProvider?(),
           !Self.englishWordAfterCaret(in: following).isEmpty {
            return false
        }
        guard let preceding = precedingTextProvider?() else {
            return true
        }
        return Self.englishWordBeforeCaret(in: preceding) == englishCurrentWord
    }

    private static func englishWordBeforeCaret(in text: String) -> String {
        var reversed: [Character] = []
        for character in text.reversed() {
            guard isEnglishWordCharacter(character) else { break }
            reversed.append(character)
        }
        return String(reversed.reversed())
    }

    private static func englishWordAfterCaret(in text: String) -> String {
        String(text.prefix(while: isEnglishWordCharacter))
    }

    private static func previousEnglishWord(in text: String) -> String {
        var remainder = text
        while let last = remainder.last, !isEnglishWordCharacter(last) {
            remainder.removeLast()
        }
        return englishWordBeforeCaret(in: remainder)
    }

    private static func isEnglishWordCharacter(_ character: Character) -> Bool {
        if character == "'" || character == "’" || character == "-" {
            return true
        }
        guard character.isLetter else { return false }
        return character.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x0041...0x007A,
                 0x00C0...0x024F,
                 0x1E00...0x1EFF:
                return true
            default:
                return false
            }
        }
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
        if FlowSessionBridge.isHostHeavy() {
            KeyboardExtensionMemoryTelemetry.record(
                "typing.rimePrepare.deferred",
                details: "hostHeavy=1"
            )
            OSGDiag.log("rime.prepare deferred hostHeavy=1 \(OSGDiag.memoryTag())", category: "boot")
            return
        }
        KeyboardExtensionMemoryTelemetry.record(
            "typing.rimePrepare.begin",
            details: "language=\(language.rawValue) "
                + "resourcesReady=\(RimeResourceInstaller.isReady ? 1 : 0)"
        )
        OSGDiag.log(
            "rime.prepare begin ready=\(RimeResourceInstaller.isReady) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        do {
            try await engine.prepare()
            engine.setLanguage(language)
            prepared = true
            engineReady = engine.isReady
            schema = engine.schema
            lastError = nil
            lastErrorNeedsHostDeployment = false
            if language == .english {
                refreshEnglishSuggestions()
            }
            KeyboardExtensionMemoryTelemetry.record(
                "typing.rimePrepare.done",
                details: "language=\(language.rawValue) ready=\(engineReady ? 1 : 0)"
            )
            OSGDiag.log(
                "rime.prepare done ready=\(engineReady) \(OSGDiag.memoryTag())",
                category: "boot"
            )
        } catch {
            lastError = error.localizedDescription
            lastErrorNeedsHostDeployment =
                (error as? RimeResourceError)?.isResolvedByHostDeployment ?? false
            engineReady = false
            KeyboardExtensionMemoryTelemetry.record(
                "typing.rimePrepare.failed",
                details: "language=\(language.rawValue) errorType=\(String(describing: type(of: error)))"
            )
            OSGDiag.log(
                "rime.prepare failed error=\(error.localizedDescription) \(OSGDiag.memoryTag())",
                category: "boot"
            )
        }
    }

    /// Retries a previously failed prepare once host-side resources land.
    /// Driven by the App Group config Darwin notification the host posts after
    /// a successful deployment, so a keyboard already showing the setup error
    /// recovers without the user switching surfaces.
    public func retryPrepareAfterResourceDeployment() {
        guard !prepared, lastError != nil else { return }
        guard prepareTask == nil else { return }
        guard RimeResourceInstaller.isReady else { return }
        OSGDiag.log("rime.prepare retry after deployment", category: "boot")
        prepareTask = Task { [weak self] in
            await self?.prepareIfNeeded()
            self?.prepareTask = nil
        }
    }
}
