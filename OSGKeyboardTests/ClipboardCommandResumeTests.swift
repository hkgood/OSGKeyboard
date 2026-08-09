// ClipboardCommandResumeTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class ClipboardCommandResumeTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ClipboardCommandResumeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testMarkPreferVoiceSurvivesUntilCleared() {
        XCTAssertFalse(ClipboardCommandResume.shouldPreferVoice(defaults: defaults))
        ClipboardCommandResume.markPreferVoice(defaults: defaults)
        XCTAssertTrue(ClipboardCommandResume.shouldPreferVoice(defaults: defaults))
        ClipboardCommandResume.clear(defaults: defaults)
        XCTAssertFalse(ClipboardCommandResume.shouldPreferVoice(defaults: defaults))
    }

    func testStoreSnapshotRoundTrip() {
        ClipboardCommandResume.storeSnapshot("周末有空一起吃饭吗？", defaults: defaults)
        XCTAssertTrue(ClipboardCommandResume.shouldPreferVoice(defaults: defaults))
        XCTAssertEqual(
            ClipboardCommandResume.pendingSnapshot(defaults: defaults),
            "周末有空一起吃饭吗？"
        )
    }

    func testOnePersistedIntentAdvancesWithoutChangingIdentity() {
        let created = ClipboardCommandResume.beginIntent(defaults: defaults)
        XCTAssertNotNil(created)
        XCTAssertEqual(created?.stage, .acquiringPaste)

        ClipboardCommandResume.storeSnapshot("需要处理的剪贴板内容", defaults: defaults)
        let warmed = ClipboardCommandResume.currentIntent(defaults: defaults)
        XCTAssertEqual(warmed?.id, created?.id)
        XCTAssertEqual(warmed?.stage, .waitingForHost)
        XCTAssertEqual(warmed?.snapshot, "需要处理的剪贴板内容")

        guard let id = created?.id else { return }
        ClipboardCommandResume.markStartIssued(id, defaults: defaults)
        let issued = ClipboardCommandResume.currentIntent(defaults: defaults)
        XCTAssertEqual(issued?.id, id)
        XCTAssertEqual(issued?.stage, .startIssued)
        XCTAssertEqual(issued?.snapshot, "需要处理的剪贴板内容")
    }

    func testCancelDeletesEntireIntentAndSnapshot() {
        let intent = ClipboardCommandResume.beginIntent(defaults: defaults)
        ClipboardCommandResume.storeSnapshot("取消后不应保留", defaults: defaults)
        if let id = intent?.id {
            ClipboardCommandResume.markStartIssued(id, defaults: defaults)
        }

        ClipboardCommandResume.clear(defaults: defaults)

        XCTAssertNil(ClipboardCommandResume.currentIntent(defaults: defaults))
        XCTAssertNil(ClipboardCommandResume.pendingSnapshot(defaults: defaults))
        XCTAssertFalse(ClipboardCommandResume.hasStartIssued(defaults: defaults))
        XCTAssertFalse(ClipboardCommandResume.shouldPreferVoice(defaults: defaults))
    }

    /// Simulates extension jetsam: writer process flushes, reader process is new.
    func testStickySurvivesNewUserDefaultsInstanceAfterSynchronize() {
        let text = "是AI语音输入法,更是好输入法。It is an AI voice input method."
        ClipboardCommandResume.markPreferVoice(defaults: defaults)
        ClipboardCommandResume.storeSnapshot(text, defaults: defaults)

        // New UserDefaults handle on the same suite ≈ new extension process.
        let reopened = UserDefaults(suiteName: suiteName!)
        XCTAssertNotNil(reopened)
        guard let reopened else { return }

        XCTAssertTrue(
            ClipboardCommandResume.shouldPreferVoice(defaults: reopened),
            "Recreated process must still prefer voice after paste-alert jetsam"
        )
        XCTAssertEqual(
            ClipboardCommandResume.pendingSnapshot(defaults: reopened),
            text
        )

        // And the open-surface policy must then force voice over default typing.
        XCTAssertEqual(
            KeyboardOpenSurfacePolicy.resolve(
                locksTypingSurface: false,
                clipboardCommandActive: false,
                stickyPreferVoice: ClipboardCommandResume.shouldPreferVoice(defaults: reopened),
                preferred: .typing
            ),
            .voice
        )
    }

    func testOpenSurfacePolicyForcesVoiceWhenStickyEvenIfDefaultTyping() {
        let resolved = KeyboardOpenSurfacePolicy.resolve(
            locksTypingSurface: false,
            clipboardCommandActive: false,
            stickyPreferVoice: true,
            preferred: .typing
        )
        XCTAssertEqual(resolved, .voice)
    }

    func testOpenSurfacePolicyHonorsDefaultTypingWhenNoSticky() {
        let resolved = KeyboardOpenSurfacePolicy.resolve(
            locksTypingSurface: false,
            clipboardCommandActive: false,
            stickyPreferVoice: false,
            preferred: .typing
        )
        XCTAssertEqual(resolved, .typing)
    }

    func testOpenSurfacePolicyClipboardActiveBeatsTypingDefault() {
        let resolved = KeyboardOpenSurfacePolicy.resolve(
            locksTypingSurface: false,
            clipboardCommandActive: true,
            stickyPreferVoice: false,
            preferred: .typing
        )
        XCTAssertEqual(resolved, .voice)
    }

    func testPasteAlertReopenDecisionMatrix() {
        // Exact bug from device: default typing + sticky after Allow Paste.
        XCTAssertEqual(
            KeyboardOpenSurfacePolicy.resolve(
                locksTypingSurface: false,
                clipboardCommandActive: false,
                stickyPreferVoice: true,
                preferred: .typing
            ),
            .voice,
            "Allow Paste reopen must not land on default Chinese typing grid"
        )

        // Recording lock also forces voice.
        XCTAssertEqual(
            KeyboardOpenSurfacePolicy.resolve(
                locksTypingSurface: true,
                clipboardCommandActive: false,
                stickyPreferVoice: false,
                preferred: .typing
            ),
            .voice
        )
    }

    func testMarkStartIssuedBlocksDuplicateRoundClaim() {
        let id = UUID()
        XCTAssertFalse(ClipboardCommandResume.hasStartIssued(defaults: defaults))
        ClipboardCommandResume.markStartIssued(id, defaults: defaults)
        XCTAssertTrue(ClipboardCommandResume.hasStartIssued(defaults: defaults))
        XCTAssertEqual(ClipboardCommandResume.startIssuedUtteranceId(defaults: defaults), id)
        XCTAssertTrue(ClipboardCommandResume.shouldPreferVoice(defaults: defaults))

        let reopened = UserDefaults(suiteName: suiteName!)
        XCTAssertEqual(
            ClipboardCommandResume.startIssuedUtteranceId(defaults: reopened),
            id,
            "Recreated extension must see the already-issued start and not send another"
        )

        ClipboardCommandResume.clear(defaults: defaults)
        XCTAssertFalse(ClipboardCommandResume.hasStartIssued(defaults: defaults))
        XCTAssertNil(ClipboardCommandResume.startIssuedUtteranceId(defaults: reopened))
    }

    func testClaimThenClearSurvivesTwentyAlternatingRounds() {
        for round in 1...20 {
            let id = UUID()
            ClipboardCommandResume.storeSnapshot("材料-\(round)", defaults: defaults)
            ClipboardCommandResume.markStartIssued(id, defaults: defaults)

            let reader = UserDefaults(suiteName: suiteName!)
            XCTAssertEqual(
                ClipboardCommandResume.startIssuedUtteranceId(defaults: reader),
                id,
                "round \(round) claim must survive new defaults handle"
            )
            XCTAssertEqual(
                KeyboardOpenSurfacePolicy.resolve(
                    locksTypingSurface: false,
                    clipboardCommandActive: false,
                    stickyPreferVoice: ClipboardCommandResume.shouldPreferVoice(defaults: reader),
                    preferred: .typing
                ),
                .voice,
                "round \(round) must stay on voice after paste-alert recreate"
            )
            XCTAssertEqual(
                ClipboardPreparingPolicy.restoreAction(
                    hasStartIssued: ClipboardCommandResume.hasStartIssued(defaults: reader),
                    phase: .idle
                ),
                .awaitExistingStart,
                "round \(round) must not pressBegan again"
            )

            ClipboardCommandResume.clear(defaults: defaults)
            XCTAssertFalse(
                ClipboardCommandResume.hasStartIssued(defaults: reader),
                "round \(round) clear must drop claim for next independent long-press"
            )
        }
    }

    func testPreparingTimeoutConstantIsPositive() {
        XCTAssertGreaterThan(ClipboardCommandResume.preparingTimeout, 1)
        XCTAssertLessThanOrEqual(ClipboardCommandResume.preparingTimeout, 15)
    }

    func testColdStartStickyRestoreResumesIntentWithoutClaim() {
        ClipboardCommandResume.storeSnapshot("冻结材料", defaults: defaults)
        XCTAssertFalse(ClipboardCommandResume.hasStartIssued(defaults: defaults))
        XCTAssertEqual(
            ClipboardPreparingPolicy.restoreAction(
                hasStartIssued: false,
                phase: .idle
            ),
            .resumeIntent
        )
        XCTAssertEqual(
            KeyboardOpenSurfacePolicy.resolve(
                locksTypingSurface: false,
                clipboardCommandActive: false,
                stickyPreferVoice: ClipboardCommandResume.shouldPreferVoice(defaults: defaults),
                preferred: .typing
            ),
            .voice,
            "Default typing keyboard must still open voice after cold-start sticky"
        )
    }
}
