// EnglishKeyboardDeviceUITests.swift
// OSGKeyboardUITests
//
// Notes-like host + the real keyboard extension on device or simulator.
// Skips only when OSGKeyboard is not enabled as the current keyboard.

import XCTest

@MainActor
final class EnglishKeyboardDeviceUITests: XCTestCase {
    func testPiPColdStartsFromUserTap() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("PiP is unavailable in the iOS Simulator.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--pip-device-ui-test"]
        let requestedCycles = ProcessInfo.processInfo.environment["PIP_STRESS_COUNT"]
            .flatMap(Int.init) ?? 30
        let cycles = min(max(requestedCycles, 1), 100)

        for cycle in 1...cycles {
            app.terminate()
            app.launch()

            let startButton = app.buttons["pip.start"]
            XCTAssertTrue(
                startButton.waitForExistence(timeout: 10),
                "Cycle \(cycle): PiP start button did not appear after cold launch."
            )
            startButton.tap()

            let ready = app.descendants(matching: .any)["pip.status.ready"]
            XCTAssertTrue(
                ready.waitForExistence(timeout: 10),
                "Cycle \(cycle): PiP did not become active after a real user tap."
            )
        }

        app.terminate()
        #endif
    }

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
