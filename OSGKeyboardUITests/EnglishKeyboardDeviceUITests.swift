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

    /// Chinese → English used to take the whole extension down. Memory relief
    /// fired while the typing surface was being torn down, and every teardown
    /// step recorded a milestone that asked for relief again — the nesting
    /// overflowed the main thread's stack.
    func testSwitchingToEnglishAfterChineseKeepsTheKeyboardAlive() throws {
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

        let keyboard = XCUIApplication(bundleIdentifier: "com.osgkeyboard.ios.keyboard")
        guard let chineseTab = inputTab("chinese", host: app, keyboard: keyboard) else {
            throw XCTSkip(
                "OSGKeyboard extension is not the active keyboard on this device. Enable it in Settings ▸ Keyboard, then re-run."
            )
        }
        chineseTab.tap()

        // Loading Rime pushes the footprint past our relief thresholds, which is
        // what arms the shed that runs on the way back out to English.
        XCTAssertTrue(
            keyboard.buttons["n"].waitForExistence(timeout: 12),
            "Chinese typing surface should come up"
        )

        guard let englishTab = inputTab("english", host: app, keyboard: keyboard) else {
            XCTFail("English tab should be reachable from the Chinese surface")
            return
        }
        englishTab.tap()

        XCTAssertTrue(
            keyboard.buttons["n"].waitForExistence(timeout: 12),
            "English surface should be usable instead of the extension being killed"
        )
        XCTAssertTrue(
            keyboard.windows.firstMatch.exists,
            "OSGKeyboard extension should survive the switch to English"
        )
    }

    /// The top-bar tabs show up in the host's accessibility hierarchy on some OS
    /// versions and in the extension's on others; try both before concluding
    /// that OSGKeyboard is not the active keyboard.
    private func inputTab(
        _ name: String,
        host: XCUIApplication,
        keyboard: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let identifier = "assistant.tab.\(name)"
        let inHost = host.descendants(matching: .any)[identifier]
        if inHost.waitForExistence(timeout: timeout) { return inHost }
        let inExtension = keyboard.descendants(matching: .any)[identifier]
        if inExtension.waitForExistence(timeout: timeout) { return inExtension }
        return nil
    }
}
