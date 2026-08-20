// TipProductTests.swift
// OSGKeyboardTests
//
// Locks tip product identifiers and optional support-count persistence.

@testable import OSGKeyboardShared
import XCTest

final class TipProductTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "tip.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testSupportProductIDIsStable() {
        XCTAssertEqual(TipProduct.supportID, "ByRockyACoffee")
        XCTAssertEqual(TipProduct.allProductIDs, [TipProduct.supportID])
    }

    func testSupportCountDefaultsKeyIsStable() {
        XCTAssertEqual(TipProduct.supportCountDefaultsKey, "tipSupportPurchaseCount")
    }

    func testSupportCountPersistsInUserDefaults() {
        defaults.set(2, forKey: TipProduct.supportCountDefaultsKey)
        XCTAssertEqual(defaults.integer(forKey: TipProduct.supportCountDefaultsKey), 2)
    }
}
