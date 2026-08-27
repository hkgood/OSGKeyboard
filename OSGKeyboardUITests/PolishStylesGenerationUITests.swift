import XCTest

final class PolishStylesGenerationUITests: XCTestCase {
    func testGeneratedStyleReviewAndSaveFlow() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "--polish-styles-screenshot",
            "--polish-styles-generation-demo"
        ]
        app.launch()

        let generate = app.buttons["polishStyles.learn.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.8)
        generate.tap()

        let save = app.buttons["polishStyles.editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
        save.tap()

        let learnedCard = app.descendants(matching: .any)[
            "polishStyles.learnedStyle.card"
        ]
        XCTAssertTrue(learnedCard.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.2)
    }
}
