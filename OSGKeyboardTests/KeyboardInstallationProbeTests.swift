// KeyboardInstallationProbeTests.swift
// OSGKeyboard · Tests

import XCTest
@testable import OSGKeyboardShared

final class KeyboardInstallationProbeTests: XCTestCase {
    func testMissingListReportsUnknownRatherThanDisabled() {
        XCTAssertNil(KeyboardInstallationProbe.isKeyboardEnabled(identifiers: nil))
    }

    func testEnabledWhenListContainsExtensionBundleID() {
        XCTAssertEqual(
            KeyboardInstallationProbe.isKeyboardEnabled(
                identifiers: ["en_US@sw=QWERTY;hw=Automatic", "com.osgkeyboard.ios.keyboard"]
            ),
            true
        )
    }

    func testDisabledWhenListOmitsExtensionBundleID() {
        XCTAssertEqual(
            KeyboardInstallationProbe.isKeyboardEnabled(
                identifiers: ["en_US@sw=QWERTY;hw=Automatic", "emoji@sw=Emoji"]
            ),
            false
        )
    }

    func testEmptyListReportsDisabled() {
        XCTAssertEqual(KeyboardInstallationProbe.isKeyboardEnabled(identifiers: []), false)
    }
}
