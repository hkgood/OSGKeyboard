// MacTextInsertionServiceTests.swift
// OSGKeyboard · Mac tests
//
// Regression coverage for clipboard preservation and captured-app context.

import AppKit
import XCTest
@testable import OSGKeyboard

final class MacTextInsertionServiceTests: XCTestCase {

    func testRestoreRequiresTranscriptToStillOwnPasteboard() {
        XCTAssertTrue(
            MacTextInsertionService.shouldRestorePasteboard(
                transcriptChangeCount: 12,
                currentChangeCount: 12
            )
        )
        XCTAssertFalse(
            MacTextInsertionService.shouldRestorePasteboard(
                transcriptChangeCount: 12,
                currentChangeCount: 13
            ),
            "A newer clipboard write must not be overwritten by restoration."
        )
    }

    func testRestoringOriginallyEmptyPasteboardClearsTranscript() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("MacTextInsertionServiceTests.\(UUID().uuidString)")
        )
        pasteboard.clearContents()
        pasteboard.setString("transcript", forType: .string)

        MacTextInsertionService.restoreItems([], to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func testCapturedBundleIdentifierDrivesPolishContext() {
        XCTAssertEqual(
            MacAppContextService.detectContext(bundleIdentifier: "com.apple.dt.Xcode"),
            .code
        )
        XCTAssertEqual(
            MacAppContextService.detectContext(bundleIdentifier: "com.tencent.xinWeChat"),
            .chat
        )
        XCTAssertEqual(
            MacAppContextService.detectContext(bundleIdentifier: "com.osgkeyboard.mac"),
            .unknown
        )
    }
}
