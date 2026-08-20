// AccountCenterUITests.swift
// OSGKeyboardUITests
//
// UI integration coverage for optional account and consumable credit flows.

import XCTest

@MainActor
final class AccountCenterUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testSignedInAccountLoadsAllCreditProducts() {
        let app = launch()

        XCTAssertTrue(element("account.center.signedIn", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("account.summary", in: app).exists)
        XCTAssertTrue(element("account.purchase.500tks", in: app).exists)
        XCTAssertTrue(element("account.purchase.1500tks", in: app).exists)
        XCTAssertTrue(element("account.purchase.3000tks", in: app).exists)
        XCTAssertTrue(element("account.purchaseHistory.link", in: app).exists)
    }

    func testVerifiedCreditPurchaseShowsSuccessState() {
        let app = launch()
        let purchase = element("account.purchase.500tks", in: app)
        XCTAssertTrue(purchase.waitForExistence(timeout: 10))

        purchase.tap()

        let status = element("account.purchase.status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("500"))
    }

    func testPurchaseHistoryOpensVerifiedTransactions() {
        let app = launch()
        let history = element("account.purchaseHistory.link", in: app)
        XCTAssertTrue(history.waitForExistence(timeout: 10))

        history.tap()

        XCTAssertTrue(
            element("account.purchaseHistory.list", in: app)
                .waitForExistence(timeout: 5)
        )
    }

    func testManagedCreditsRequireFirstUseCloudConsent() {
        let app = launch(arguments: ["--managed-consent-ui-test"])
        let managed = element("settings.aiService.managed", in: app)
        XCTAssertTrue(managed.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: managed)
        waitForExpectations(timeout: 5)

        managed.tap()

        let accept = app.buttons
            .matching(identifier: "settings.aiService.credits.consent.accept")
            .firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        XCTAssertEqual(managed.value as? String, "notSelected")

        accept.tap()

        expectation(
            for: NSPredicate(format: "value == 'selected'"),
            evaluatedWith: managed
        )
        waitForExpectations(timeout: 5)

        let byok = element("settings.aiService.byok", in: app)
        byok.tap()
        expectation(
            for: NSPredicate(format: "value == 'selected'"),
            evaluatedWith: byok
        )
        waitForExpectations(timeout: 5)

        managed.tap()
        expectation(
            for: NSPredicate(format: "value == 'selected'"),
            evaluatedWith: managed
        )
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.alerts.count, 0)
    }

    private func launch(arguments: [String] = ["--account-ui-test"]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
