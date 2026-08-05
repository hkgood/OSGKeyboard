// KeyboardTranslationConfigProtectionTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class KeyboardTranslationConfigProtectionTests: XCTestCase {

    func testGraceWindowProtectsUntilDeadline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let deadline = KeyboardTranslationConfigProtection.protectionDeadline(now: now)
        XCTAssertEqual(
            deadline.timeIntervalSince(now),
            KeyboardTranslationConfigProtection.chipWriteGraceSeconds,
            accuracy: 0.001
        )
        XCTAssertTrue(
            KeyboardTranslationConfigProtection.shouldProtect(until: deadline, now: now)
        )
        XCTAssertTrue(
            KeyboardTranslationConfigProtection.shouldProtect(
                until: deadline,
                now: now.addingTimeInterval(2.4)
            )
        )
        XCTAssertFalse(
            KeyboardTranslationConfigProtection.shouldProtect(
                until: deadline,
                now: deadline
            )
        )
        XCTAssertFalse(
            KeyboardTranslationConfigProtection.shouldProtect(until: nil, now: now)
        )
    }
}
