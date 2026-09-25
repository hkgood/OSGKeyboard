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

/// Covers the *acting* half of the memory guard. The budget thresholds above
/// were always correct; what was missing was anything that used them. A
/// keyboard extension gets no reliable system memory warning before jetsam,
/// so these thresholds are the only chance to shed load before the keyboard
/// is killed mid-sentence.
@MainActor
final class KeyboardExtensionMemoryReliefTests: XCTestCase {
    override func tearDown() {
        KeyboardExtensionMemoryTelemetry.reliefHandler = nil
        KeyboardExtensionMemoryTelemetry.stopSampling()
        super.tearDown()
    }

    private func armedLevels(
        accepting: Bool = true
    ) -> (record: () -> [KeyboardExtensionMemoryBudget.Level], reset: () -> Void) {
        let box = LevelBox()
        KeyboardExtensionMemoryTelemetry.begin(context: "test")
        KeyboardExtensionMemoryTelemetry.stopSampling()
        KeyboardExtensionMemoryTelemetry.reliefHandler = { level in
            box.levels.append(level)
            return accepting
        }
        return ({ box.levels }, { box.levels.removeAll() })
    }

    @MainActor
    private final class LevelBox {
        var levels: [KeyboardExtensionMemoryBudget.Level] = []
    }

    func testNormalAndWarningFootprintsDoNotShed() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(20)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(37)
        XCTAssertEqual(levels(), [])
    }

    func testHighFootprintRequestsSoftRelief() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(41)
        XCTAssertEqual(levels(), [.high])
    }

    func testSustainedPressureDoesNotReshedAtTheSameLevel() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        // Ten seconds of polling above the threshold. A timed cooldown would
        // have shed three more times by now; hysteresis sheds once.
        for _ in 0..<10 {
            KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        }
        XCTAssertEqual(levels(), [.critical])
    }

    func testPressureMustRecedeBelowWarningBeforeSheddingAgain() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        // Landing back in the warning band is where a shed leaves the keyboard;
        // treating that as recovery would re-arm on the very next sample.
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(37)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        XCTAssertEqual(levels(), [.critical])

        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(22)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        XCTAssertEqual(levels(), [.critical, .critical])
    }

    func testDeclinedReliefStaysArmedForTheNextPoll() {
        let (levels, _) = armedLevels(accepting: false)
        // The host declines while the user is mid-composition. Recording it as
        // a completed shed would leave the keyboard at 48 MiB, having released
        // nothing, until pressure receded on its own.
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        XCTAssertEqual(levels(), [.critical, .critical, .critical])
    }

    func testReliefIsNeverRequestedFromInsideRelief() {
        let box = LevelBox()
        KeyboardExtensionMemoryTelemetry.begin(context: "test")
        KeyboardExtensionMemoryTelemetry.stopSampling()
        KeyboardExtensionMemoryTelemetry.reliefHandler = { level in
            box.levels.append(level)
            // Shedding records milestones, and recording samples memory again.
            // Without the reentrancy gate this re-entered the handler until the
            // main thread's stack ran out — the crash this test pins down.
            KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
            return true
        }
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        XCTAssertEqual(box.levels, [.critical])
    }

    func testRepeatedHighFootprintShedsOnce() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(41)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(42)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(43)
        // One shed per level per episode: re-tearing down the typing surface on
        // every 1 s poll would make the keyboard unusable, not safer.
        XCTAssertEqual(levels(), [.high])
    }

    func testEscalationToCriticalShedsEvenAfterASoftShed() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(41)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        // The hard shed must not wait out a soft one — 49 MiB is ~11 MiB from
        // the observed jetsam boundary.
        XCTAssertEqual(levels(), [.high, .critical])
    }

    func testCriticalDoesNotDownshiftBackToHigh() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(41)
        XCTAssertEqual(levels(), [.critical])
    }

    func testNewSessionCanShedAgain() {
        let (levels, _) = armedLevels()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(49)
        XCTAssertEqual(levels(), [.critical])
        // `begin` is called once per extension process; a reused process must
        // not inherit the previous presentation's armed state.
        KeyboardExtensionMemoryTelemetry.begin(context: "test-2")
        KeyboardExtensionMemoryTelemetry.stopSampling()
        KeyboardExtensionMemoryTelemetry.simulateFootprintForTesting(41)
        XCTAssertEqual(levels(), [.critical, .high])
    }
}
