import XCTest

@MainActor
final class EditPagerUITests: XCTestCase {
    func testPagerSwipesBetweenOriginalAndEditedText() {
        let app = XCUIApplication()
        app.launchArguments = ["--edit-pager-ui-test"]
        app.launch()

        let swipeArea = app.descendants(matching: .any)["edit.pager.swipeArea"]
        XCTAssertTrue(swipeArea.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["ORIGINAL_ACTIVE"].waitForExistence(timeout: 5))

        // Start from app coordinates, not the ScrollView accessibility
        // element. Element-relative injection can bypass real screen hit
        // testing and previously let a transparent dead zone pass this test.
        let appFrame = app.frame
        let areaFrame = swipeArea.frame
        let y = areaFrame.minY + areaFrame.height * 0.9
        let rightX = areaFrame.minX + areaFrame.width * 0.88
        let leftX = areaFrame.minX + areaFrame.width * 0.12
        let lowerRight = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (rightX - appFrame.minX) / appFrame.width,
                dy: (y - appFrame.minY) / appFrame.height
            )
        )
        let lowerLeft = app.coordinate(
            withNormalizedOffset: CGVector(
                dx: (leftX - appFrame.minX) / appFrame.width,
                dy: (y - appFrame.minY) / appFrame.height
            )
        )
        lowerRight.press(forDuration: 0.05, thenDragTo: lowerLeft)
        XCTAssertTrue(app.staticTexts["EDITED_ACTIVE"].waitForExistence(timeout: 5))

        lowerLeft.press(forDuration: 0.05, thenDragTo: lowerRight)
        XCTAssertTrue(app.staticTexts["ORIGINAL_ACTIVE"].waitForExistence(timeout: 5))
    }
}
