import XCTest

@MainActor
final class AssistantKeyboardUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testTapRoutesToOrdinaryDictation() {
        let app = launch(scenario: "idle")
        let idleMic = element("assistant.mic.idle", in: app)
        XCTAssertTrue(idleMic.waitForExistence(timeout: 10))

        idleMic.tap()

        XCTAssertTrue(
            element("assistant.mic.dictationRecording", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(element("assistant.action.send", in: app).isHittable)
    }

    func testIdleHintHasBalancedSpacingAndFullCapsuleHitTarget() {
        let app = launch(scenario: "idle")
        let tab = requiredElement("assistant.tab.assistant", in: app)
        let hint = requiredElement("assistant.hint", in: app)
        let mic = requiredElement("assistant.mic.idle", in: app)

        let topGap = hint.frame.minY - tab.frame.maxY
        let bottomGap = mic.frame.minY - hint.frame.maxY
        XCTAssertEqual(topGap, bottomGap, accuracy: 2)
        XCTAssertTrue(hint.isHittable)

        hint.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let waitingMic = element("assistant.mic.aiGenerating", in: app)
        XCTAssertTrue(waitingMic.waitForExistence(timeout: 3))
        XCTAssertFalse(waitingMic.isEnabled)
    }

    func testTranslationPrecedesClipboardOnTrailingEdge() {
        let app = launch(scenario: "idle")
        let translation = requiredElement("assistant.translation", in: app)
        let clipboard = requiredElement("assistant.clipboard", in: app)

        XCTAssertLessThan(translation.frame.midX, clipboard.frame.midX)
    }

    func testSkillFailureCapsuleFollowsTextWidth() {
        let app = launch(scenario: "skillFailure")
        let tip = requiredElement("assistant.skillTip", in: app)

        XCTAssertLessThan(tip.frame.width, 180)
    }

    func testHoldRoutesToAIListeningWithoutAlsoStartingDictation() {
        let app = launch(scenario: "idle")
        let idleMic = element("assistant.mic.idle", in: app)
        XCTAssertTrue(idleMic.waitForExistence(timeout: 10))

        idleMic.press(forDuration: 0.7)

        let listeningMic = element("assistant.mic.aiListening", in: app)
        XCTAssertTrue(listeningMic.waitForExistence(timeout: 3))
        XCTAssertFalse(element("assistant.mic.dictationRecording", in: app).exists)

        listeningMic.tap()

        let waitingMic = element("assistant.mic.aiRecognizing", in: app)
        XCTAssertTrue(waitingMic.waitForExistence(timeout: 3))
        XCTAssertFalse(waitingMic.isEnabled)
    }

    func testCompletedInputRevealsUndoEditAndSendWithoutOverlap() {
        let app = launch(scenario: "completed")
        let mic = requiredElement("assistant.mic.idle", in: app)
        let delete = requiredElement("assistant.delete", in: app)
        let space = requiredElement("assistant.space", in: app)
        let undo = requiredElement("assistant.undo", in: app)
        let edit = requiredElement("assistant.edit", in: app)
        let send = requiredElement("assistant.action.send", in: app)

        XCTAssertTrue(send.isEnabled)
        assertNoIntersection(delete, mic)
        assertNoIntersection(space, mic)
        assertNoIntersection(undo, send)
        assertNoIntersection(edit, send)
        XCTAssertGreaterThan(send.frame.minY, mic.frame.maxY)
    }

    func testEditButtonRunsStopAndConfirmCycle() {
        let app = launch(scenario: "completed")

        requiredElement("assistant.edit", in: app).tap()
        let stop = requiredElement("assistant.edit.stop", in: app)
        XCTAssertTrue(stop.isHittable)

        stop.tap()
        let confirm = requiredElement("assistant.edit.confirm", in: app)
        XCTAssertTrue(confirm.isHittable)

        confirm.tap()
        XCTAssertTrue(
            element("assistant.mic.idle", in: app)
                .waitForExistence(timeout: 3)
        )
    }

    func testChangedTargetAnswerCanBeInsertedExplicitly() {
        let app = launch(scenario: "pending")
        let insert = requiredElement("assistant.pending.insert", in: app)
        XCTAssertTrue(element("assistant.pending.discard", in: app).exists)
        XCTAssertTrue(
            app.staticTexts["A retained answer that requires explicit insertion."].exists
        )

        insert.tap()

        XCTAssertTrue(
            element("assistant.mic.idle", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(requiredElement("assistant.action.send", in: app).isEnabled)
        XCTAssertTrue(element("assistant.undo", in: app).exists)
        XCTAssertTrue(element("assistant.edit", in: app).exists)
    }

    func testClipboardSkillsPageHorizontallyAndDismissTogether() {
        let app = launch(scenario: "skills")
        let pager = requiredElement("assistant.skills.pager", in: app)
        let navigate = element("assistant.skill.navigate", in: app)
        let sideActions = [
            requiredElement("assistant.delete", in: app),
            requiredElement("assistant.space", in: app),
            requiredElement("assistant.undo", in: app),
            requiredElement("assistant.edit", in: app)
        ]

        for action in sideActions {
            XCTAssertTrue(action.isHittable)
        }

        pager.swipeLeft()

        XCTAssertTrue(navigate.waitForExistence(timeout: 3))
        XCTAssertTrue(navigate.isHittable)

        requiredElement("assistant.clipboard.dismiss", in: app).tap()

        XCTAssertTrue(
            element("assistant.mic.idle", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(element("assistant.skills.pager", in: app).exists)
    }

    func testSearchFieldShowsEnabledSearchAction() {
        let app = launch(scenario: "search")
        let search = requiredElement("assistant.action.search", in: app)

        XCTAssertTrue(search.isEnabled)
        XCTAssertTrue(search.isHittable)
    }

    func testActionGeometrySurvivesLandscapeRotation() {
        let app = launch(scenario: "completed")
        _ = requiredElement("assistant.mic.idle", in: app)

        XCUIDevice.shared.orientation = .landscapeLeft

        let mic = requiredElement("assistant.mic.idle", in: app)
        let delete = requiredElement("assistant.delete", in: app)
        let space = requiredElement("assistant.space", in: app)
        let undo = requiredElement("assistant.undo", in: app)
        let edit = requiredElement("assistant.edit", in: app)
        let send = requiredElement("assistant.action.send", in: app)
        assertNoIntersection(delete, mic)
        assertNoIntersection(space, mic)
        assertNoIntersection(undo, send)
        assertNoIntersection(edit, send)
    }

    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--assistant-ui-test",
            "--assistant-state=\(scenario)",
        ]
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func requiredElement(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let match = element(identifier, in: app)
        XCTAssertTrue(match.waitForExistence(timeout: 10), "Missing \(identifier)")
        return match
    }

    private func assertNoIntersection(
        _ first: XCUIElement,
        _ second: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            first.frame.intersects(second.frame),
            "\(first.identifier) overlaps \(second.identifier)",
            file: file,
            line: line
        )
    }
}
