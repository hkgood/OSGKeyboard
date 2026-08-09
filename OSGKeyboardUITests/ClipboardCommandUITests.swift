// ClipboardCommandUITests.swift
// OSGKeyboard · UI Tests (device reproduction harness)
//
// Drives the real long-press → 「允许粘贴」 → clipboard-command round on a
// physical device, which is the only path Apple exposes for injecting touches
// outside the Simulator. Pair with an Instruments capture so the unified log of
// both the host app and the keyboard extension can be replayed per round:
//
//   xcrun xctrace record --device <UDID> --template Logging --all-processes \
//       --output round.trace
//
// Knobs (environment, read at runtime):
//   OSG_ROUNDS        number of long-press rounds            (default 5)
//   OSG_ALLOW_DELAY   seconds to leave the paste alert up    (default 1.0)
//   OSG_SETTLE        seconds to observe after allowing      (default 12)
//   OSG_PICK_KEYBOARD set to 1 to long-press globe and pick OSGKeyboard

import XCTest
import UIKit
import os

@MainActor
final class ClipboardCommandUITests: XCTestCase {

    private let log = Logger(subsystem: "com.osgkeyboard.uitest", category: "round")
    private lazy var app = XCUIApplication()
    private lazy var springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private var rounds: Int { Int(env("OSG_ROUNDS") ?? "") ?? 5 }
    private var allowDelay: TimeInterval { Double(env("OSG_ALLOW_DELAY") ?? "") ?? 1.0 }
    private var settle: TimeInterval { Double(env("OSG_SETTLE") ?? "") ?? 12 }

    private func env(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: - Test

    func testClipboardLongPressRounds() throws {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "host app did not foreground")
        mark("session.begin rounds=\(rounds) allowDelay=\(allowDelay)")

        attach("launch")
        mark("launch.tree textViews=\(app.textViews.count) textFields=\(app.textFields.count) "
             + "keyboards=\(app.keyboards.count) buttons=\(app.buttons.count) "
             + "tabs=\(app.tabBars.buttons.count)")

        focusPreviewField()
        attach("after-focus")
        try selectOSGKeyboardIfRequested()

        for round in 1...rounds {
            runRound(round)
        }
        mark("session.end")
    }

    // MARK: - Round

    private func runRound(_ round: Int) {
        let text = "第\(round)轮剪贴板命令测试文本，请把它改写得更正式一些。"

        // Recording chrome only listens for taps (long-press is idle-only).
        // Clear any leftover「指令录制中」before we seed the next round.
        focusPreviewField()
        stopRecordingIfNeeded(tag: "round.\(round).preclear")

        // UITest Runner on device cannot write UIPasteboard.general (PBErrorDomain
        // Code=10/11). Seed via the host text field + system edit menu instead.
        let seeded = seedClipboardViaHostField(text)
        mark("round.\(round).pasteboardSeeded=\(seeded)")

        focusPreviewField()
        attach("r\(round)-before-press")
        mark("round.\(round).longPress.begin")
        mic.press(forDuration: 1.2)

        let allowed = handlePasteAlert(round: round)
        mark("round.\(round).pasteAlert allowed=\(allowed)")

        let deadline = Date().addingTimeInterval(settle)
        var frame = 0
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 2.0)
            frame += 1
            attach("r\(round)-settle-\(frame)")
        }

        // Tap-to-stop after observation — exercises the exit path users use.
        stopRecordingIfNeeded(tag: "round.\(round).poststop")
        mark("round.\(round).end")
        dismissKeyboard()
    }

    /// While phase is recording/processing the mic only has `onTapGesture`.
    /// A XCUITest long-press will not stop an active clipboard utterance.
    private func stopRecordingIfNeeded(tag: String) {
        attach("\(tag)-before-tap")
        mic.tap()
        Thread.sleep(forTimeInterval: 1.2)
        attach("\(tag)-after-tap")
        mark("\(tag) mic.tap")
    }

    /// The system paste-consent alert is owned by SpringBoard, not the app.
    private func handlePasteAlert(round: Int) -> Bool {
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN {'允许粘贴', 'Allow Paste'}")
        ).firstMatch
        // Also try the host app hierarchy — some iOS builds host the sheet there.
        let allowInApp = app.buttons.matching(
            NSPredicate(format: "label IN {'允许粘贴', 'Allow Paste'}")
        ).firstMatch
        let button: XCUIElement
        if allow.waitForExistence(timeout: 4) {
            button = allow
        } else if allowInApp.waitForExistence(timeout: 4) {
            button = allowInApp
        } else {
            return false
        }

        attach("r\(round)-alert")
        // Hold the alert open so wall-clock deadlines armed before the press
        // can be pushed past their expiry — the failure mode under test.
        Thread.sleep(forTimeInterval: allowDelay)
        mark("round.\(round).allowTap")
        button.tap()
        return true
    }

    // MARK: - Clipboard seeding

    /// Put `text` on the device pasteboard by typing into the host preview field
    /// and using Select All → Copy. Returns whether Copy appeared and was tapped.
    @discardableResult
    private func seedClipboardViaHostField(_ text: String) -> Bool {
        let field = previewField()
        guard field.waitForExistence(timeout: 8) else {
            mark("seed.fail noPreviewField")
            return false
        }
        field.tap()
        Thread.sleep(forTimeInterval: 0.4)

        // Clear whatever is already there so typeText does not append forever.
        clearPreviewField(field)

        field.typeText(text)
        Thread.sleep(forTimeInterval: 0.4)
        attach("seed-typed")

        // Long-press to summon the edit menu.
        field.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.5)

        if !tapMenuItem(labels: ["全选", "Select All"]) {
            // Double-tap often selects a word; try again for Select All.
            field.doubleTap()
            Thread.sleep(forTimeInterval: 0.4)
            _ = tapMenuItem(labels: ["全选", "Select All"])
        }
        Thread.sleep(forTimeInterval: 0.3)

        let copied = tapMenuItem(labels: ["拷贝", "Copy"])
        mark("seed.copy tapped=\(copied)")
        attach("seed-after-copy")

        // Tap elsewhere to dismiss the menu, then clear the field so the next
        // long-press exercises clipboard content rather than field text.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20)).tap()
        Thread.sleep(forTimeInterval: 0.3)
        field.tap()
        clearPreviewField(field)
        return copied
    }

    private func clearPreviewField(_ field: XCUIElement) {
        // Select-all + delete via menu when possible; fall back to delete key events.
        let current = field.value as? String ?? ""
        guard !current.isEmpty, current != "点这里试试键盘" else { return }
        field.press(forDuration: 1.0)
        if tapMenuItem(labels: ["全选", "Select All"]) {
            Thread.sleep(forTimeInterval: 0.2)
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            return
        }
        // Fallback: spam delete for the current length (capped).
        let n = min(current.count, 80)
        let deletes = String(repeating: XCUIKeyboardKey.delete.rawValue, count: n)
        field.typeText(deletes)
    }

    @discardableResult
    private func tapMenuItem(labels: [String]) -> Bool {
        for label in labels {
            let item = app.menuItems[label]
            if item.waitForExistence(timeout: 1.5) {
                item.tap()
                return true
            }
            let springItem = springboard.menuItems[label]
            if springItem.waitForExistence(timeout: 0.5) {
                springItem.tap()
                return true
            }
        }
        return false
    }

    // MARK: - Keyboard plumbing

    // A custom keyboard extension is not published as `app.keyboards` on a
    // physical device, so every key is addressed by normalized screen offset.
    // Measured against the OSG voice surface on iPhone 15 Pro Max.
    private var mic: XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.78))
    }

    private var globe: XCUICoordinate {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.098, dy: 0.958))
    }

    private func previewField() -> XCUIElement {
        if app.textFields.firstMatch.exists { return app.textFields.firstMatch }
        return app.textViews.firstMatch
    }

    private func focusPreviewField() {
        let field = previewField()
        if field.waitForExistence(timeout: 10) {
            field.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)).tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func dismissKeyboard() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        Thread.sleep(forTimeInterval: 1.0)
    }

    /// Only needed when the device is not already left on the OSG keyboard.
    private func selectOSGKeyboardIfRequested() throws {
        guard env("OSG_PICK_KEYBOARD") == "1" else { return }
        globe.press(forDuration: 1.3)
        let entry = app.buttons["OSGKeyboard"].exists
            ? app.buttons["OSGKeyboard"]
            : springboard.buttons["OSGKeyboard"]
        if entry.waitForExistence(timeout: 6) {
            entry.tap()
        }
        Thread.sleep(forTimeInterval: 2.0)
        attach("keyboard-selected")
        mark("keyboard.picked")
    }

    // MARK: - Evidence

    private func mark(_ message: String) {
        log.info("[uitest] \(message, privacy: .public)")
        print("[uitest] \(message)")
    }

    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
