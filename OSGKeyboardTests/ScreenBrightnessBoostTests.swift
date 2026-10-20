// ScreenBrightnessBoostTests.swift
// OSGKeyboardTests
//
// Whatever order holds and scene changes arrive in, the user's own
// brightness must come back once nothing needs the boost.

@testable import OSGKeyboard
import XCTest

@MainActor
final class ScreenBrightnessBoostTests: XCTestCase {
    private final class FakeScreen: ScreenBrightnessControlling {
        var brightness: CGFloat
        init(brightness: CGFloat) { self.brightness = brightness }
    }

    func testHoldRaisesBrightnessAndReleaseRestoresIt() {
        let screen = FakeScreen(brightness: 0.4)
        let boost = ScreenBrightnessBoost { screen }

        boost.acquire()
        XCTAssertEqual(screen.brightness, 1)

        boost.release()
        XCTAssertEqual(screen.brightness, 0.4)
    }

    func testOverlappingHoldsKeepTheOriginalLevel() {
        let screen = FakeScreen(brightness: 0.3)
        let boost = ScreenBrightnessBoost { screen }

        // A new view appears before the previous one disappears.
        boost.acquire()
        boost.acquire()
        boost.release()
        XCTAssertEqual(screen.brightness, 1)

        boost.release()
        XCTAssertEqual(screen.brightness, 0.3)
    }

    func testBackgroundRestoresAndForegroundReapplies() {
        let screen = FakeScreen(brightness: 0.5)
        let boost = ScreenBrightnessBoost { screen }
        boost.acquire()

        boost.setInForeground(false)
        XCTAssertEqual(screen.brightness, 0.5)

        boost.setInForeground(true)
        XCTAssertEqual(screen.brightness, 1)

        boost.release()
        XCTAssertEqual(screen.brightness, 0.5)
    }

    func testUnbalancedReleaseLeavesBrightnessAlone() {
        let screen = FakeScreen(brightness: 0.6)
        let boost = ScreenBrightnessBoost { screen }

        boost.release()
        boost.acquire()
        XCTAssertEqual(screen.brightness, 1)

        boost.release()
        XCTAssertEqual(screen.brightness, 0.6)
    }

    func testMissingScreenIsRetriedOnTheNextChange() {
        var screen: FakeScreen?
        let boost = ScreenBrightnessBoost { screen }

        boost.acquire()
        screen = FakeScreen(brightness: 0.2)
        boost.setInForeground(true)
        XCTAssertEqual(screen?.brightness, 1)

        boost.release()
        XCTAssertEqual(screen?.brightness, 0.2)
    }
}
