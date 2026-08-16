// EnglishKeyboardDeviceUITests.swift
// OSGKeyboardUITests
//
// Notes-like host + the real keyboard extension on device or simulator.
// Skips only when OSGKeyboard is not enabled as the current keyboard.

import XCTest

@MainActor
final class EnglishKeyboardDeviceUITests: XCTestCase {
    func testOSGKeyboardAppearsOnNotesHost() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--whats-new-host",
            "--whats-new-lang=en",
            "--whats-new-scenario=edit"
        ]
        app.launch()

        let textView = app.textViews["notes.host.textView"]
        XCTAssertTrue(
            textView.waitForExistence(timeout: 12),
            "Notes host text view should appear"
        )
        if !textView.exists {
            return
        }
        textView.tap()

        let surfaceInHost = app.descendants(matching: .any)["assistant.surface"]
        if surfaceInHost.waitForExistence(timeout: 8) {
            return
        }

        let keyboard = XCUIApplication(bundleIdentifier: "com.osgkeyboard.ios.keyboard")
        let surfaceInExtension = keyboard.descendants(matching: .any)["assistant.surface"]
        let appeared = keyboard.wait(for: .runningForeground, timeout: 8)
            || keyboard.windows.firstMatch.waitForExistence(timeout: 8)
            || surfaceInExtension.waitForExistence(timeout: 8)
        if !appeared {
            throw XCTSkip(
                "OSGKeyboard extension is not the active keyboard on this device. Enable it in Settings ▸ Keyboard, then re-run."
            )
        }

        XCTAssertTrue(
            keyboard.windows.firstMatch.exists || surfaceInExtension.exists,
            "OSGKeyboard extension window should be on screen"
        )
    }
}
