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
        OSGDiag.log(
            "typing.enter begin lang=\(language.rawValue) schema=\(schema.rawValue) "
                + "hostHeavy=\(FlowSessionBridge.isHostHeavy() ? 1 : 0) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        TypingInputConfiguration.shared.reload()
        refreshPersonalTerms()
        // English lexicon is small; load when entering typing (not at KVC init).
        englishEngine.prepare()
        OSGDiag.log("typing.enter after englishPrepare \(OSGDiag.memoryTag())", category: "boot")
        syncAutocapitalization()
        if FlowSessionBridge.isHostHeavy() {
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
        // Drop English lexicon pages when leaving typing (jetsam recovery).
        EnglishLexicon.shared.unload()
        englishStorage = nil
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
        resetShiftState()
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
            clearOneShotShiftIfNeeded()
            refreshEnglishSuggestions()
            return .insert(String(ch))
        }

        // Punctuation / digit: commit current word first, then insert.
        var output = commitEnglishWord(suffix: "")
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
            clearOneShotShiftIfNeeded()
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
        guard !capsLock, !shiftHeld, !shiftPrimedByUser else { return }
        let mode = autocapitalizationModeProvider?() ?? .sentences
        let preceding = resolvedPrecedingText(
            accountingForInsert: insert,
            deleteCount: deleteCount
        )
        shiftActive = TypingAutocapitalization.shouldCapitalize(
            precedingText: preceding,
            mode: mode
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
        if FlowSessionBridge.isHostHeavy() {
            OSGDiag.log("rime.prepare deferred hostHeavy=1 \(OSGDiag.memoryTag())", category: "boot")
            return
        }
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
            if language == .english {
                refreshEnglishSuggestions()
            }
            OSGDiag.log(
                "rime.prepare done ready=\(engineReady) \(OSGDiag.memoryTag())",
                category: "boot"
            )
        } catch {
            lastError = error.localizedDescription
            engineReady = false
            OSGDiag.log(
                "rime.prepare failed error=\(error.localizedDescription) \(OSGDiag.memoryTag())",
                category: "boot"
            )
        }
    }
}
