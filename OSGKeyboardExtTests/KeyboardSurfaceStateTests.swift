// KeyboardSurfaceStateTests.swift
// OSGKeyboard · Ext unit tests

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class KeyboardSurfaceStateTests: XCTestCase {
    @MainActor
    func testBusyAISessionLocksOtherSurfacesAndShowsCancel() {
        let state = KeyboardState()
        state.surface = .ai
        state.aiSession.enter()
        state.aiSession.beginPreparing(utteranceID: UUID())

        XCTAssertTrue(state.locksTypingSurface)
        XCTAssertTrue(state.canCancelAIInput)
    }

    func testRecordingLocksTyping() {
        let state = KeyboardState()
        state.phase = .idle
        XCTAssertTrue(state.canEnterTypingSurface)
        state.phase = .recording
        XCTAssertTrue(state.locksTypingSurface)
        XCTAssertFalse(state.canEnterTypingSurface)
    }

    func testNormalVoicePipelineCanBeCancelledUntilItReturnsIdle() {
        let state = KeyboardState()
        state.phase = .requestingPermissions
        XCTAssertTrue(state.canCancelVoiceInput)
        state.phase = .recording
        XCTAssertTrue(state.canCancelVoiceInput)
        state.phase = .processing
        XCTAssertTrue(state.canCancelVoiceInput)
        state.phase = .idle
        XCTAssertFalse(state.canCancelVoiceInput)

        let reference = EditableInputReference(
            displayText: "原文",
            insertedText: "原文",
            postInsertionFingerprint: nil,
            extensionInstanceID: UUID()
        )
        state.editSession = .listening(EditSessionSource(reference: reference))
        state.phase = .recording
        XCTAssertFalse(state.canCancelVoiceInput)
    }

    func testStandardLayoutHasQwertyTopRow() {
        let layout = StandardTypingLayout()
        let rows = layout.rows(for: .letters, language: .english, shiftActive: false)
        XCTAssertEqual(rows.first, ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"])
        let shifted = layout.rows(for: .letters, language: .english, shiftActive: true)
        XCTAssertEqual(shifted.first?.first, "Q")
    }

    func testEnglishNumberAndSymbolPagesMatchIOSUS() {
        let layout = StandardTypingLayout()
        XCTAssertEqual(
            layout.rows(for: .numbers, language: .english, shiftActive: false),
            [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                ["#+=", ".", ",", "?", "!", "'", "⌫"]
            ]
        )
        XCTAssertEqual(
            layout.rows(for: .symbols, language: .english, shiftActive: false),
            [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
                ["123", ".", ",", "?", "!", "'", "⌫"]
            ]
        )
    }

    func testChineseNumberAndSymbolPagesMatchIOSSimplified() {
        let layout = StandardTypingLayout()
        XCTAssertEqual(
            layout.rows(for: .numbers, language: .chinese, shiftActive: false),
            [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", "：", "；", "（", "）", "￥", "@", "“", "”"],
                ["#+=", "。", "，", "、", "？", "！", ".", "⌫"]
            ]
        )
        XCTAssertEqual(
            layout.rows(for: .symbols, language: .chinese, shiftActive: false),
            [
                ["【", "】", "「", "」", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "《", "》", "€", "£", "¥", "·"],
                ["123", "。", "，", "、", "？", "！", ".", "⌫"]
            ]
        )
    }

    func testKeyRowsFollowTypingLanguageOnNumberPage() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        typing.setPage(.numbers)
        XCTAssertEqual(typing.keyRows[1], ["-", "/", "：", "；", "（", "）", "￥", "@", "“", "”"])

        _ = typing.setLanguage(.english)
        typing.setPage(.numbers)
        XCTAssertEqual(typing.keyRows[1], ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""])
    }

    func testVoiceAndTypingChromeShareStableDimensions() {
        XCTAssertEqual(KeyboardChromeLayout.totalHeight, 281)
        XCTAssertEqual(KeyboardChromeLayout.actionKeyHeight, 50)
        XCTAssertEqual(KeyboardChromeLayout.actionKeyCornerRadius, 10)
        XCTAssertEqual(KeyboardChromeLayout.actionKeySpacing, 8)
        // Globe key now sits at the far-left of every bottom action row, so the
        // four-slot layout splits 12 / 18 / 50 / 20 of the residual width.
        XCTAssertEqual(KeyboardChromeLayout.globeActionKeyFraction, 0.12)
        XCTAssertEqual(KeyboardChromeLayout.sideActionKeyFraction, 0.18)
        XCTAssertEqual(KeyboardChromeLayout.centerActionKeyFraction, 0.50)
        XCTAssertEqual(KeyboardChromeLayout.side2ActionKeyFraction, 0.20)
        XCTAssertEqual(KeyboardChromeLayout.horizontalInset, 8)
        // Voice-surface only. The typing grid is uncapped so it can match the
        // system keyboard's absolute key positions on iPad.
        XCTAssertEqual(KeyboardChromeLayout.voiceContentMaxWidth, 700)

        let widths = KeyboardChromeLayout.actionKeyWidths(availableWidth: 374)
        // availableWidth 374 − 3 × spacing 8 = 350 of key width
        XCTAssertEqual(widths.globe, 42, accuracy: 0.001)
        XCTAssertEqual(widths.side, 63, accuracy: 0.001)
        XCTAssertEqual(widths.center, 175, accuracy: 0.001)
        XCTAssertEqual(widths.side2, 70, accuracy: 0.001)

        let phoneWidths = KeyboardChromeLayout.actionKeyWidthsWithoutGlobe(
            availableWidth: 374
        )
        // 374 − 2 × spacing 8 = 358pt, redistributed across the three
        // remaining slots without changing their relative proportions.
        XCTAssertEqual(phoneWidths.side, 73.227, accuracy: 0.001)
        XCTAssertEqual(phoneWidths.center, 203.409, accuracy: 0.001)
        XCTAssertEqual(phoneWidths.side2, 81.364, accuracy: 0.001)

        let iPadWidths = KeyboardChromeLayout.iPadVoiceActionKeyWidths(
            availableWidth: 1024
        )
        // 1024 − 3 × 8 = 1000pt: keep the globe compact and give return 40%.
        XCTAssertEqual(iPadWidths.globe, 100, accuracy: 0.001)
        XCTAssertEqual(iPadWidths.side, 240, accuracy: 0.001)
        XCTAssertEqual(iPadWidths.center, 400, accuracy: 0.001)
        XCTAssertEqual(iPadWidths.side2, 260, accuracy: 0.001)
    }

    func testIPhoneTypingBottomRowOmitsCustomGlobeAndFillsWidth() {
        let layout = TypingKeyLayoutBuilder.build(
            size: CGSize(width: 374, height: 281),
            letterRows: [
                ["q", "w"],
                ["a", "s"],
                ["z", "x"]
            ],
            pageSwitchLabel: "123",
            spaceLabel: "空格",
            returnLabel: "return",
            includeGlobeKey: false,
            keyWeight: { _, _, _ in 1 }
        )

        XCTAssertNil(layout.key(id: TypingKeyLayoutBuilder.BottomKeyID.globe.rawValue))
        let slots = [
            TypingKeyLayoutBuilder.BottomKeyID.pageSwitch.rawValue,
            TypingKeyLayoutBuilder.BottomKeyID.space.rawValue,
            TypingKeyLayoutBuilder.BottomKeyID.return.rawValue
        ]
        let used = slots.compactMap { layout.key(id: $0)?.visualFrame.width }.reduce(0, +)
        XCTAssertEqual(
            used + KeyboardChromeLayout.actionKeySpacing * 2,
            374,
            accuracy: 0.001
        )
    }

    func testIPadMetricsRequirePadAndRegularWidth() {
        XCTAssertTrue(
            KeyboardChromeLayout.usesIPadMetrics(
                isPad: true,
                hasRegularWidth: true
            )
        )
        XCTAssertFalse(
            KeyboardChromeLayout.usesIPadMetrics(
                isPad: true,
                hasRegularWidth: false
            ),
            "Compact iPad multitasking must use the compact layout"
        )
        XCTAssertFalse(
            KeyboardChromeLayout.usesIPadMetrics(
                isPad: false,
                hasRegularWidth: true
            ),
            "Wide iPhones must never opt into iPad metrics"
        )
    }

    func testRimeDeploymentRejectsAppExtensionProcess() {
        XCTAssertFalse(
            RimeResourceInstaller.canDeploy(
                bundleURL: URL(fileURLWithPath: "/tmp/OSGKeyboardExt.appex")
            )
        )
        XCTAssertTrue(
            RimeResourceInstaller.canDeploy(
                bundleURL: URL(fileURLWithPath: "/tmp/OSGKeyboard.app")
            )
        )
    }

    func testWideIPadMetricsTrackWidthNotOrientation() {
        // iPad portrait widths (744 mini … 1024 on 13") stay narrow.
        XCTAssertFalse(KeyboardChromeLayout.usesWideIPadMetrics(isIPad: true, width: 834))
        XCTAssertFalse(KeyboardChromeLayout.usesWideIPadMetrics(isIPad: true, width: 1024))
        // iPad landscape widths (1133 mini … 1366 on 13") go wide.
        XCTAssertTrue(KeyboardChromeLayout.usesWideIPadMetrics(isIPad: true, width: 1133))
        XCTAssertTrue(KeyboardChromeLayout.usesWideIPadMetrics(isIPad: true, width: 1366))
        // A wide iPhone must never reach iPad metrics, however wide it gets.
        XCTAssertFalse(KeyboardChromeLayout.usesWideIPadMetrics(isIPad: false, width: 1366))
    }

    func testTypingHeightGrowsWithAvailableWidth() {
        let phone = TypingSurfaceMetrics.contentHeight(isIPad: false, width: 393)
        let portrait = TypingSurfaceMetrics.contentHeight(isIPad: true, width: 834)
        let landscape = TypingSurfaceMetrics.contentHeight(isIPad: true, width: 1194)

        XCTAssertEqual(phone, KeyboardChromeLayout.totalHeight)
        XCTAssertGreaterThan(portrait, phone)
        XCTAssertGreaterThan(
            landscape,
            portrait,
            "A full-width landscape grid needs taller rows or keys turn flat"
        )
    }

    func testSecondRowInsetKeepsKeysAsWideAsTheFirstRow() {
        // 10 keys on row 0, 9 on row 1, all weight 1 — the classic QWERTY/ASDF
        // relationship. Row 1 should be inset by exactly half a key pitch.
        let layout = TypingKeyLayoutBuilder.build(
            size: CGSize(width: 1194, height: 400),
            letterRows: [
                ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
                ["Z", "X", "C", "V", "B", "N", "M"]
            ],
            pageSwitchLabel: "123",
            spaceLabel: "space",
            returnLabel: "return",
            metrics: TypingKeyLayoutBuilder.Metrics(derivesSecondRowInsetFromKeyWidth: true),
            keyWeight: { _, _, _ in 1 }
        )

        let q = layout.key(id: "grid.0.0")!
        let a = layout.key(id: "grid.1.0")!
        XCTAssertEqual(
            a.visualFrame.width,
            q.visualFrame.width,
            accuracy: 0.001,
            "Second-row keys must match first-row key width at any total width"
        )
        // Row 1 is centred: its inset equals half of one key plus one gap.
        let expectedInset = (q.visualFrame.width + layout.horizontalGap) / 2
        XCTAssertEqual(a.visualFrame.minX, expectedInset, accuracy: 0.001)
    }

    func testIPadBottomRowAddsPunctuationAndKeepsSpaceUsable() {
        let rows = [
            ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
            ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
            ["⇧", "Z", "X", "C", "V", "B", "N", "M", "⌫"]
        ]
        func bottomRow(punctuation: TypingKeyLayoutBuilder.PunctuationKeys?) -> TypingKeyLayout {
            TypingKeyLayoutBuilder.build(
                size: CGSize(width: 1178, height: 400),
                letterRows: rows,
                pageSwitchLabel: "123",
                spaceLabel: "space",
                returnLabel: "return",
                metrics: TypingKeyLayoutBuilder.Metrics(derivesSecondRowInsetFromKeyWidth: true),
                punctuationKeys: punctuation,
                keyWeight: { _, _, _ in 1 }
            )
        }

        let phoneStyle = bottomRow(punctuation: nil)
        let iPadStyle = bottomRow(punctuation: .init(comma: "，", period: "。"))

        // Without punctuation the 50% centre fraction is a runway.
        let wideSpace = phoneStyle.key(id: "bottom.space")!.visualFrame.width
        XCTAssertGreaterThan(wideSpace, 550)

        let space = iPadStyle.key(id: "bottom.space")!.visualFrame.width
        XCTAssertLessThan(space, wideSpace)
        XCTAssertEqual(space, 432, accuracy: 1, "Space should land near the system's ~430 pt")

        XCTAssertEqual(iPadStyle.key(id: "bottom.comma")?.label, "，")
        XCTAssertEqual(iPadStyle.key(id: "bottom.period")?.label, "。")
        XCTAssertNil(phoneStyle.key(id: "bottom.comma"))

        // The row must still consume exactly the available width.
        let slots = ["bottom.globe", "bottom.page", "bottom.comma",
                     "bottom.space", "bottom.period", "bottom.return"]
        let used = slots.compactMap { iPadStyle.key(id: $0)?.visualFrame.width }.reduce(0, +)
        let gaps = KeyboardChromeLayout.actionKeySpacing * 5
        XCTAssertEqual(used + gaps, 1178, accuracy: 0.5)
    }

    func testOnlyHostDeployableRimeErrorsOfferTheSetupJump() {
        // These are fixed by deploying resources in the host app, so the
        // keyboard should surface a tappable jump.
        XCTAssertTrue(RimeResourceError.resourcesNotInstalled.isResolvedByHostDeployment)
        XCTAssertTrue(RimeResourceError.deploymentFailed.isResolvedByHostDeployment)
        XCTAssertTrue(
            RimeResourceError.bundledResourceMissing("osg_pinyin.dict.yaml")
                .isResolvedByHostDeployment
        )
        // These resolve on their own; sending the user to the app does nothing.
        XCTAssertFalse(RimeResourceError.appGroupUnavailable.isResolvedByHostDeployment)
        XCTAssertFalse(RimeResourceError.lockUnavailable.isResolvedByHostDeployment)
    }

    func testResourceRetryIsSkippedWhenNoErrorIsPending() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        XCTAssertNil(typing.lastError)
        XCTAssertFalse(typing.lastErrorNeedsHostDeployment)

        // No prior failure — a config-change notification must not kick off a
        // prepare, otherwise every host settings write would wake the engine.
        typing.retryPrepareAfterResourceDeployment()

        XCTAssertNil(typing.lastError)
        XCTAssertFalse(typing.engineReady)
    }

    func testSharedCapsuleCanSelectSpecificTypingLanguage() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        XCTAssertEqual(typing.language, .chinese)

        XCTAssertEqual(typing.setLanguage(.english), .none)
        XCTAssertEqual(typing.language, .english)

        XCTAssertEqual(typing.setLanguage(.chinese), .none)
        XCTAssertEqual(typing.language, .chinese)
    }

    func testShiftStateProducesUppercaseKeyRows() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        XCTAssertFalse(typing.shiftActive)

        _ = typing.handleKey("⇧")

        XCTAssertTrue(typing.shiftActive)
        XCTAssertTrue(typing.isShiftEnabled)
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }

    func testManualShiftSurvivesAutocapitalizationSync() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        // Providers must be set before language switch (which syncs autocap).
        typing.precedingTextProvider = { "hello " } // mid-sentence: auto stays off
        typing.autocapitalizationModeProvider = { .sentences }
        _ = typing.setLanguage(.english)
        XCTAssertFalse(typing.shiftActive)

        _ = typing.handleKey("⇧")
        XCTAssertTrue(typing.shiftActive)

        typing.syncAutocapitalization()
        XCTAssertTrue(typing.shiftActive, "manual one-shot must outrank autocap sync")
        XCTAssertEqual(typing.keyRows.first?.first, "Q")
    }

    func testShiftHoldTypesUppercaseWithoutEnteringCapsLock() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        _ = typing.setLanguage(.english)
        typing.precedingTextProvider = { "hello " }
        typing.autocapitalizationModeProvider = { .sentences }

        typing.beginShiftHold()
        XCTAssertTrue(typing.shiftHeld)
        XCTAssertEqual(typing.keyRows.first?.first, "Q")

        _ = typing.handleKey("S")
        _ = typing.handleKey("m")
        XCTAssertFalse(typing.capsLock)

        typing.endShiftHold()
        XCTAssertFalse(typing.shiftHeld)
        XCTAssertFalse(typing.capsLock)
        XCTAssertFalse(typing.shiftActive)
    }

    func testShiftHoldWithoutTypingActsAsTap() {
        let typing = TypingSessionController(engine: { TrackingStubRimeEngine() })
        typing.beginShiftHold()
        typing.endShiftHold()
        XCTAssertTrue(typing.shiftActive)
        XCTAssertFalse(typing.shiftHeld)
        XCTAssertFalse(typing.capsLock)
    }

    func testChineseShiftInsertsUppercaseLatinBypassingRime() {
        let engine = TrackingStubRimeEngine()
        let typing = TypingSessionController(engine: { engine })

        _ = typing.handleKey("⇧")
        XCTAssertTrue(typing.shiftActive)

        let output = typing.handleKey("N")
        XCTAssertEqual(output, .insert("N"))
        XCTAssertEqual(engine.processCharacterCallCount, 0)
        XCTAssertFalse(typing.shiftActive, "one-shot Shift clears after Latin insert")
        XCTAssertTrue(typing.composition.preedit.isEmpty)
    }

    func testChineseShiftPreservesExistingComposition() {
        let engine = TrackingStubRimeEngine()
        let typing = TypingSessionController(engine: { engine })
        // Seed session composition via a lowercase letter (goes to Rime).
        _ = typing.handleKey("n")
        XCTAssertEqual(typing.composition.preedit, "n")

        _ = typing.handleKey("⇧")
        let output = typing.handleKey("A")
        XCTAssertEqual(output, .insert("A"))
        XCTAssertEqual(engine.processCharacterCallCount, 1, "only the unshifted letter hits Rime")
        XCTAssertEqual(typing.composition.preedit, "n", "Shift Latin must not clear preedit")
    }

    func testChineseCapsLockKeepsInsertingUppercaseLatin() {
        let engine = TrackingStubRimeEngine()
        let typing = TypingSessionController(engine: { engine })

        _ = typing.handleKey("⇧")
        _ = typing.handleKey("⇧") // second tap → Caps Lock
        XCTAssertTrue(typing.capsLock)

        XCTAssertEqual(typing.handleKey("O"), .insert("O"))
        XCTAssertEqual(typing.handleKey("S"), .insert("S"))
        XCTAssertEqual(engine.processCharacterCallCount, 0)
        XCTAssertTrue(typing.capsLock)
    }

    func testChineseUnshiftedLetterStillComposes() {
        let engine = TrackingStubRimeEngine()
        let typing = TypingSessionController(engine: { engine })

        let output = typing.handleKey("n")
        XCTAssertEqual(output, .none)
        XCTAssertEqual(engine.processCharacterCallCount, 1)
        XCTAssertEqual(engine.lastProcessedCharacter, "n")
        XCTAssertEqual(typing.composition.preedit, "n")
    }

    func testSecureFieldInsertsLatinWithoutRime() {
        let engine = TrackingStubRimeEngine()
        let typing = TypingSessionController(engine: { engine })

        _ = typing.handleKey("n")
        XCTAssertEqual(engine.processCharacterCallCount, 1)

        typing.suggestionsEnabled = false
        XCTAssertTrue(typing.composition.preedit.isEmpty)
        XCTAssertEqual(engine.clearCompositionCallCount, 1)

        XCTAssertEqual(typing.handleKey("a"), .insert("a"))
        XCTAssertEqual(engine.processCharacterCallCount, 1)
        XCTAssertEqual(typing.handleSpace(), .insert(" "))
        XCTAssertEqual(engine.processSpaceCallCount, 0)
        XCTAssertEqual(typing.selectCandidate(at: 0), .none)
    }
}

/// Stub that records `processCharacter` calls for Chinese Shift bypass tests.
@MainActor
private final class TrackingStubRimeEngine: RimeEngineBridging {
    var composition: TypingComposition = .empty
    var isReady: Bool = true
    var schema: TypingInputSchema = .fullPinyin
    private(set) var processCharacterCallCount = 0
    private(set) var processSpaceCallCount = 0
    private(set) var clearCompositionCallCount = 0
    private(set) var lastProcessedCharacter: Character?

    func prepare() async throws {}
    func teardown() { composition = .empty }

    func setLanguage(_ language: TypingInputLanguage) {
        if language == .english { composition = .empty }
    }

    @discardableResult
    func setSchema(_ schema: TypingInputSchema) -> Bool {
        self.schema = schema
        return true
    }

    func processCharacter(_ character: Character) -> String? {
        processCharacterCallCount += 1
        lastProcessedCharacter = character
        composition = TypingComposition(
            preedit: String(character).lowercased(),
            candidates: [TypingCandidate(text: "你")]
        )
        return nil
    }

    func processBackspace() -> String? {
        composition = .empty
        return nil
    }

    func processSpace() -> String? {
        processSpaceCallCount += 1
        composition = .empty
        return " "
    }

    func processReturn() -> String? {
        composition = .empty
        return "\n"
    }

    func selectCandidate(at index: Int) -> String {
        composition = .empty
        return ""
    }

    func flushPreedit() -> String {
        let raw = composition.preedit
        composition = .empty
        return raw
    }

    func clearComposition() {
        clearCompositionCallCount += 1
        composition = .empty
    }
}
