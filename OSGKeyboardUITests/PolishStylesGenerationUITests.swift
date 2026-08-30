import XCTest

final class PolishStylesGenerationUITests: XCTestCase {
    func testTestBuildRequiresTwelveFiftyCharacterMinimum() {
        // The old "unlimited" test-mode bypass has been removed. Test
        // builds now enforce a 1,250-character minimum: an empty corpus
        // must keep the generation button disabled, and the visible
        // progress text should reflect the remaining distance to the
        // active gate.
        continueAfterFailure = false
        let app = launchServiceHarness(
            additionalArgument: "--polish-styles-service-ui-test-no-corpus"
        )

        let generate = app.buttons["polishStyles.learn.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertFalse(
            generate.isEnabled,
            "Empty corpus in a test build must not unlock generation; the 1,250-character minimum still applies."
        )
        XCTAssertFalse(
            app.staticTexts[
                "Test build: 2,500-character limit disabled"
            ].exists,
            "The old unlimited-bypass label must no longer be shown."
        )
    }

    func testGeneratedStyleReviewAndSaveFlow() {
        continueAfterFailure = false
        let app = launchServiceHarness()

        let generate = app.buttons["polishStyles.learn.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        let save = app.buttons["polishStyles.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        let promptEditor = app.textViews["polishStyles.editor.prompt"]
        XCTAssertTrue(promptEditor.waitForExistence(timeout: 2))
        XCTAssertTrue(
            (promptEditor.value as? String)?.contains("natural, direct voice") == true,
            "The real learning service must pass the scripted synthesis into review"
        )
        save.tap()

        let learnedCard = app.descendants(matching: .any)[
            "polishStyles.learnedStyle.card"
        ]
        XCTAssertTrue(learnedCard.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Confidence: 86%"].exists)
    }

    func testInsufficientEvidenceIsDisclosedDuringReviewAndAfterSave() {
        continueAfterFailure = false
        let app = launchServiceHarness(usesInsufficientEvidence: true)

        let generate = app.buttons["polishStyles.learn.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        let warning = app.staticTexts[
            "Low confidence. The prompt was generated from limited evidence; please review it."
        ]
        XCTAssertTrue(warning.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Confidence: 20%"].exists)

        let save = app.buttons["polishStyles.editor.save"]
        XCTAssertTrue(save.exists)
        save.tap()

        let learnedCard = app.descendants(matching: .any)[
            "polishStyles.learnedStyle.card"
        ]
        XCTAssertTrue(learnedCard.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.waitForExistence(timeout: 2))
    }

    func testRegenerationPreservesExistingStyleIdentityUntilSave() {
        continueAfterFailure = false
        let app = launchServiceHarness(
            additionalArgument: "--polish-styles-service-ui-test-regenerate"
        )
        let learnedCard = app.descendants(matching: .any)[
            "polishStyles.learnedStyle.card"
        ]
        XCTAssertTrue(learnedCard.waitForExistence(timeout: 5))
        let regenerate = app.buttons["Regenerate"]
        XCTAssertTrue(regenerate.exists)
        let originalID = regenerate.value as? String
        XCTAssertFalse(originalID?.isEmpty ?? true)

        regenerate.tap()
        let save = app.buttons["polishStyles.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 8))
        XCTAssertEqual(
            regenerate.value as? String,
            originalID,
            "The persisted style must remain unchanged while review is open"
        )
        save.tap()

        XCTAssertTrue(learnedCard.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.buttons["Regenerate"].value as? String,
            originalID
        )
    }

    func testSynthesisFailureKeepsExistingStyleUnchanged() {
        continueAfterFailure = false
        let app = launchServiceHarness(
            additionalArgument: "--polish-styles-service-ui-test-failure"
        )
        let learnedCard = app.descendants(matching: .any)[
            "polishStyles.learnedStyle.card"
        ]
        XCTAssertTrue(learnedCard.waitForExistence(timeout: 5))
        let regenerate = app.buttons["Regenerate"]
        let originalID = regenerate.value as? String

        regenerate.tap()
        XCTAssertTrue(
            app.staticTexts["Couldn’t Generate Style"].waitForExistence(timeout: 8)
        )
        XCTAssertEqual(regenerate.value as? String, originalID)
        XCTAssertFalse(app.buttons["polishStyles.editor.save"].exists)
    }

    func testLeavingStyleScreenCancelsGenerationWithoutTimeoutAlert() {
        continueAfterFailure = false
        let app = launchServiceHarness(
            additionalArgument: "--polish-styles-service-ui-test-cancel"
        )
        let generate = app.buttons["polishStyles.learn.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        let leave = app.buttons["polishStyles.test.leave"]
        XCTAssertTrue(leave.exists)
        leave.tap()
        XCTAssertTrue(
            app.staticTexts["polishStyles.test.closed"].waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts["polishStyles.test.cancelled"].waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.staticTexts["Couldn’t Generate Style"].exists)
    }

    private func launchServiceHarness(
        usesInsufficientEvidence: Bool = false,
        additionalArgument: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--polish-styles-screenshot",
            "--polish-styles-service-ui-test",
            "--screenshot-lang=en"
        ]
        if usesInsufficientEvidence {
            app.launchArguments.append(
                "--polish-styles-service-ui-test-insufficient"
            )
        }
        if let additionalArgument {
            app.launchArguments.append(additionalArgument)
        }
        app.launch()
        return app
    }
}
