// KeyboardExtensionMemoryBudgetTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class KeyboardExtensionMemoryBudgetTests: XCTestCase {
    func testMemoryLevelsUseDocumentedBoundaries() {
        XCTAssertEqual(
            KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: 35.9),
            .normal
        )
        XCTAssertEqual(
            KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: 36),
            .warning
        )
        XCTAssertEqual(
            KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: 40),
            .high
        )
        XCTAssertEqual(
            KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: 48),
            .critical
        )
    }

    func testUnavailableFootprintIsNotMisclassifiedAsSafe() {
        XCTAssertEqual(
            KeyboardExtensionMemoryBudget.level(forPhysFootprintMB: -1),
            .unavailable
        )
    }
}
