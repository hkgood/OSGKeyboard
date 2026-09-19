// ClipboardCaptureCoordinator.swift
// OSGKeyboard · Keyboard Extension
//
// Samples the general pasteboard on keyboard appear and while visible
// (changeCount-driven). Writes accepted text into ClipboardHistoryStore.

import Combine
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
    private let semanticRanking: ClipboardSemanticRankingStore
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
    /// OOBE reply / translate practice auto-fires once per feature so the user
    /// sees the keyboard draft the result without tapping the chip. Tracked per
    /// feature (the host keeps one session id across every practice step).
    private var oobeAutoFiredSessionID: UUID?
    private var oobeAutoFiredFeatures: Set<ManagedGatewayOOBEFeature> = []
    /// Fires the auto-reply evaluation whenever a fresh semantic analysis lands,
    /// independent of which keyboard surface (voice / Chinese / English) is shown.
    private var snapshotObserver: AnyCancellable?

    init(
        state: KeyboardState,
        history: ClipboardHistoryStore = .shared,
        semanticRanking: ClipboardSemanticRankingStore = .shared,
        pasteboard: ClipboardPasteboardProviding = SystemClipboardPasteboard()
    ) {
        self.state = state
        self.history = history
        self.semanticRanking = semanticRanking
        self.pasteboard = pasteboard
        snapshotObserver = semanticRanking.$snapshot
            .sink { [weak self] snapshot in
                // `@Published` fires in willSet, so the store's property is not
                // updated yet; hop to the main actor so the trigger reads the
                // published snapshot (and satisfies actor isolation).
                guard snapshot != nil else { return }
                Task { @MainActor in
                    self?.autoTriggerActionIfNeeded()
                    self?.presentAutoReplyGuideIfNeeded()
                }
            }
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
        if let newest = history.newestAIHintEligibleEntry() {
            semanticRanking.analyze(newest)
        }
        forcesNextSample = true
        autoTriggerOOBESkillIfNeeded()
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
        semanticRanking.clear()
    }

    func refreshFlagsFromStore() {
        // Paste is available whenever clipboard history is on; only turning
        // history off hides it (the old candidate-bar toggle is gone).
        if !state.clipboardHistoryEnabled {
            endCurrentSuggestion()
            semanticRanking.clear()
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
        semanticRanking.clear()
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
        // Dismissing from either surface must suppress both the paste capsule
        // AND the AI skill top bar for this clipboard generation. The typing
        // surface's X only routes here, so set the skill marker centrally
        // rather than relying on the AI surface's own dismiss handler.
        state.dismissedClipboardSkillEntryID = history.newestEntry?.id
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
        semanticRanking.clear()
        history.clearAll()
    }

    func deleteEntry(id: UUID) {
        let deletedChangeCount = history.entries.first(where: { $0.id == id })?.changeCount
        history.remove(id: id)
        if semanticRanking.snapshot?.entryID == id {
            semanticRanking.clear()
        }
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
                self?.autoTriggerOOBESkillIfNeeded()
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
            semanticRanking.clear()
            history.lastObservedChangeCount = changeCount
            return
        }

        let raw = pasteboard.string
        // The forced appearance read exists only to establish/refresh iOS
        // paste permission. It must not reinsert or republish old content.
        if isCurrentGeneration {
            return
        }
        semanticRanking.clear()
        if let entry = history.ingest(rawText: raw, changeCount: changeCount) {
            semanticRanking.analyze(entry)
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
            semanticRanking.clear()
            history.lastObservedChangeCount = changeCount
            return
        }
        // Forced appearance reads establish iOS paste permission only. Never
        // republish content from an already observed generation.
        guard !isCurrentGeneration else { return }

        semanticRanking.clear()
        if let entry = history.ingest(rawText: sample.text, changeCount: changeCount) {
            semanticRanking.analyze(entry)
            updateSuggestion(with: entry, changeCount: changeCount)
        } else {
            history.lastObservedChangeCount = changeCount
        }
    }

    private func updateSuggestion(with entry: ClipboardHistoryEntry, changeCount: Int) {
        // The one-tap Paste capsule is always on (its old opt-in toggle was
        // removed), so this only depends on clipboard history + a secure field.
        guard state.canShowClipboardEntry,
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

    // MARK: - Auto mode

    /// Auto mode: on every fresh semantic analysis, pick at most one automatic
    /// action for the newest clipboard and route it into the assistant surface
    /// with no tap. Surface-independent (voice / Chinese / English) and fired at
    /// most once per pasteboard generation, persisted so a reopen never repeats.
    ///
    /// Precedence when several toggles apply to the same paste:
    /// email reply (a detected email should be answered, not just translated —
    /// even in another language) → translate (foreign, non-email) → generic reply.
    private func autoTriggerActionIfNeeded() {
        guard state.clipboardHistoryEnabled,
              state.aiServiceAvailable,
              state.oobePracticeSession == nil,
              isKeyboardVisible,
              isRestingForAutoReply else {
            return
        }
        guard state.clipboardAutoModeEnabled
                || state.clipboardAutoTranslateEnabled
                || state.clipboardAutoEmailReplyEnabled else {
            return
        }
        guard let newest = history.newestEntry,
              let changeCount = newest.changeCount else {
            return
        }
        // One auto action per copy, even across keyboard close/reopen.
        guard history.lastAutoRepliedChangeCount != changeCount else { return }
        guard AIHintPool.isClipboardSkillWindowActive(
            clipboardHistoryEnabled: state.clipboardHistoryEnabled,
            newestClipboard: newest
        ) else {
            return
        }
        guard let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id else {
            return
        }
        let catalog = state.clipboardSkillCatalog

        // 1. Auto-draft a single, email-formatted reply for a detected email.
        //    Checked before translate so a foreign-language email is answered
        //    rather than merely translated. Staged like auto-translate: shown on
        //    the keyboard, inserted only on the glass button.
        if state.clipboardAutoEmailReplyEnabled,
           ClipboardEmailDetector.isEmail(newest.text) {
            fireAutoAction(
                AIClipboardSkillCatalog.emailReplySkill,
                scene: nil,
                changeCount: changeCount,
                readOnlyResult: true,
                insertLabelKey: "keyboard.assistant.insertReply"
            )
            return
        }
        // 2. Auto-translate a non-system-language, non-email paste (staged).
        if state.clipboardAutoTranslateEnabled,
           ClipboardSkillSemanticRanker.isForeignLanguage(snapshot.analysis),
           let translate = catalog.first(where: { $0.id == AIClipboardSkillCatalog.translateID }) {
            fireAutoAction(translate, scene: nil, changeCount: changeCount, readOnlyResult: true)
            return
        }
        // 3. Auto-reply for any interpersonal message worth answering — a task,
        //    question, invitation, complaint, follow-up, or an explicit "please
        //    reply". Gated on reply intent (not strict #1 ranking) so a message
        //    that also scores Events / Todos / Summary still auto-replies. Bare
        //    links / phones / foreign text keep their own actions.
        if state.clipboardAutoModeEnabled,
           ClipboardSkillSemanticRanker.isAutoReplyEligible(
               sourceText: newest.text,
               analysis: snapshot.analysis
           ),
           let reply = catalog.first(where: { $0.id == AIClipboardSkillCatalog.replyID }) {
            fireAutoAction(
                reply,
                scene: AIClipboardReplyScene.resolve(
                    from: snapshot.analysis,
                    sourceText: newest.text
                ),
                changeCount: changeCount,
                readOnlyResult: false
            )
        }
    }

    /// Submit the chosen auto action, remembering the keyboard to return to and
    /// taking over the assistant surface so the result is visible.
    private func fireAutoAction(
        _ skill: AIClipboardSkill,
        scene: AIClipboardReplyScene?,
        changeCount: Int,
        readOnlyResult: Bool,
        insertLabelKey: String = "keyboard.assistant.insertTranslation"
    ) {
        // Mark handled before submitting so re-entrant publishes cannot double-fire.
        history.lastAutoRepliedChangeCount = changeCount
        // Remember the keyboard to return to once the result is used or closed:
        // the surface the user is actively on, or — when the keyboard opened
        // straight onto voice — the one they last left, so finishing never
        // strands them on voice input. nil means "already where we'd land".
        let returnSurface: KeyboardState.Surface = state.surface != .voice
            ? state.surface
            : TypingInputConfiguration.lastLeftSurface()
        state.autoReplyReturnSurface = returnSurface == .voice ? nil : returnSurface
        // Staged auto results (translate / email reply) wait for a glass-button
        // tap; generic replies use their own variant surface.
        state.autoResultReadOnly = readOnlyResult
        state.autoResultInsertLabelKey = insertLabelKey
        // The result UI only renders on the assistant surface, so take it over.
        if state.surface != .voice {
            state.setSurface(.voice)
        }
        state.submitAIClipboardSkill(skill, scene)
    }

    // MARK: - Auto-reply guide (one-time nudge)

    /// Persisted "the user has already responded to the nudge once" flag. Stored
    /// in the extension's own defaults; the guide is a keyboard-local affordance.
    private static let autoReplyGuideTriedKey = "keyboard.assistant.autoReplyGuidanceTried"
    private static var autoReplyGuideTried: Bool {
        get { UserDefaults.standard.bool(forKey: autoReplyGuideTriedKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoReplyGuideTriedKey) }
    }
    /// Only auto-present once per pasteboard generation, so dismissing the layer
    /// does not immediately resurface it for the same copy.
    private var lastGuidedChangeCount: Int?

    /// For users who never turned auto mode on: when a freshly copied message
    /// reads as replyable, raise the clean full-keyboard guide instead of firing
    /// a reply. Shown on every replyable copy until the user acts on it once.
    private func presentAutoReplyGuideIfNeeded() {
        guard !state.clipboardAutoModeEnabled,
              !Self.autoReplyGuideTried,
              state.clipboardHistoryEnabled,
              state.aiServiceAvailable,
              state.oobePracticeSession == nil,
              state.canShowClipboardEntry,
              state.clipboardOverlay == .none,
              isKeyboardVisible,
              isRestingForAutoReply else {
            return
        }
        guard let newest = history.newestEntry,
              let changeCount = newest.changeCount,
              lastGuidedChangeCount != changeCount else {
            return
        }
        guard AIHintPool.isClipboardSkillWindowActive(
            clipboardHistoryEnabled: state.clipboardHistoryEnabled,
            newestClipboard: newest
        ) else {
            return
        }
        guard let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id else {
            return
        }
        let recommended = ClipboardSkillSemanticRanker.recommended(
            skills: state.clipboardSkillCatalog,
            sourceText: newest.text,
            analysis: snapshot.analysis,
            uiLanguage: state.uiLanguage,
            limit: 5
        )
        guard recommended.first?.id == AIClipboardSkillCatalog.replyID else { return }
        lastGuidedChangeCount = changeCount
        state.clipboardOverlay = .autoReplyGuide
    }

    /// The guide's primary action: opt into auto mode (persisted so it sticks),
    /// close the layer, and draft the reply for the copy that prompted it — the
    /// same submission every future auto reply now makes on its own.
    func confirmAutoReplyGuide() {
        Self.autoReplyGuideTried = true
        AppGroupStore().setClipboardAutoModeEnabled(true)
        state.clipboardAutoModeEnabled = true
        state.clipboardOverlay = .none
        guard let newest = history.newestEntry,
              let snapshot = semanticRanking.snapshot,
              snapshot.entryID == newest.id,
              let reply = state.clipboardSkillCatalog.first(where: {
                  $0.id == AIClipboardSkillCatalog.replyID
              }) else {
            return
        }
        let scene = AIClipboardReplyScene.resolve(
            from: snapshot.analysis,
            sourceText: newest.text
        )
        fireAutoAction(
            reply,
            scene: scene,
            changeCount: newest.changeCount ?? history.lastObservedChangeCount,
            readOnlyResult: false
        )
    }

    /// OOBE reply / translate practice: once the host has seeded the demo
    /// message, run the skill automatically — the same submission the chip makes
    /// — so the user experiences the auto skill before any setting is turned on.
    /// Runs off the poll tick (OOBE material is not semantic-ranked), and fires
    /// at most once per practice feature within the host session. The translate
    /// result is staged (glass Insert button) exactly like the live auto flow.
    private func autoTriggerOOBESkillIfNeeded() {
        guard let session = state.oobePracticeSession,
              state.aiServiceAvailable,
              isKeyboardVisible,
              isRestingForAutoReply else {
            return
        }
        let feature = session.expectedFeature
        let skillID: String
        switch feature {
        case .clipboardReply:
            skillID = AIClipboardSkillCatalog.replyID
        case .clipboardTranslate:
            skillID = AIClipboardSkillCatalog.translateID
        case .voiceInput, .askAI:
            return
        }
        // The host keeps one session id across steps, so gate per feature.
        if oobeAutoFiredSessionID != session.sessionID {
            oobeAutoFiredSessionID = session.sessionID
            oobeAutoFiredFeatures = []
        }
        guard !oobeAutoFiredFeatures.contains(feature) else { return }
        guard KeyboardSetupBridge.oobeClipboardMaterial(
            sessionID: session.sessionID
        ) != nil else {
            return
        }
        guard let skill = state.clipboardSkillCatalog.first(where: {
            $0.id == skillID
        }) else {
            return
        }
        // Mark handled before submitting so a re-entrant tick cannot double-fire.
        oobeAutoFiredFeatures.insert(feature)
        // Stage the translation like the live auto-translate: shown on the
        // keyboard, inserted only when the user taps the glass button.
        if feature == .clipboardTranslate {
            state.autoResultReadOnly = true
            state.autoResultInsertLabelKey = "keyboard.assistant.insertTranslation"
        }
        // The result UI only renders on the assistant surface, so take it over.
        if state.surface != .voice {
            state.setSurface(.voice)
        }
        state.submitAIClipboardSkill(skill, nil)
    }

    /// The voice pipeline must be idle before auto mode takes over the surface.
    private var isRestingForAutoReply: Bool {
        guard !state.aiSession.isBusy,
              !state.aiSession.canInsert,
              !state.aiSession.canSelectReplyVariant,
              !state.editSession.isActive else {
            return false
        }
        switch state.phase {
        case .idle, .error, .denied:
            return true
        case .requestingPermissions, .recording, .processing:
            return false
        }
    }
}
