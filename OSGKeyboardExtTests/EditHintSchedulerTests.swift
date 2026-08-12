// EditHintSchedulerTests.swift
// OSGKeyboard · Keyboard Extension Tests

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class EditHintSchedulerTests: XCTestCase {
    func testShowPublishesImmediately() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Unavailable", isPositive: false, duration: .seconds(2.5))

        XCTAssertEqual(state.editHint, "Unavailable")
        XCTAssertFalse(state.editHintIsPositive)

        await sleeper.waitForRequestCount(1)
        scheduler.invalidate()
        sleeper.resumeAll()
        await drainTasks()
    }

    func testForwardsErrorAndPositiveDurations() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Failure", isPositive: false, duration: .milliseconds(2_500))
        await sleeper.waitForRequestCount(1)
        scheduler.show(message: "Available", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(2)

        XCTAssertEqual(sleeper.recordedDurations, [.milliseconds(2_500), .seconds(10)])

        scheduler.invalidate()
        sleeper.resumeAll()
        await drainTasks()
    }

    func testExpirationClearsHint() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Available", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(1)
        sleeper.resumeFirst()
        await drainTasks()

        XCTAssertNil(state.editHint)
        XCTAssertFalse(state.editHintIsPositive)
    }

    func testSameMessageABADoesNotLetOldExpirationClearNewHint() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Same", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(1)
        scheduler.show(message: "Same", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(2)

        sleeper.resumeFirst()
        await drainTasks()
        XCTAssertEqual(state.editHint, "Same")
        XCTAssertTrue(state.editHintIsPositive)

        sleeper.resumeFirst()
        await drainTasks()
        XCTAssertNil(state.editHint)
        XCTAssertFalse(state.editHintIsPositive)
    }

    func testOldTaskThatIgnoresCancellationCannotClearNewHint() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Old", isPositive: false, duration: .seconds(2.5))
        await sleeper.waitForRequestCount(1)
        scheduler.show(message: "New", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(2)

        // ControlledSleeper intentionally ignores cancellation and still wakes
        // the old task, so generation is the only correctness boundary.
        sleeper.resumeFirst()
        await drainTasks()

        XCTAssertEqual(state.editHint, "New")
        XCTAssertTrue(state.editHintIsPositive)

        scheduler.invalidate()
        sleeper.resumeAll()
        await drainTasks()
    }

    func testClearPositiveDoesNotClearFailure() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Failure", isPositive: false, duration: .seconds(2.5))
        await sleeper.waitForRequestCount(1)
        scheduler.clearPositive()

        XCTAssertEqual(state.editHint, "Failure")
        XCTAssertFalse(state.editHintIsPositive)

        sleeper.resumeFirst()
        await drainTasks()
        XCTAssertNil(state.editHint)
        XCTAssertFalse(state.editHintIsPositive)
    }

    func testInvalidateClearsAndPreventsDelayedWriteBack() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        let scheduler = makeScheduler(state: state, sleeper: sleeper)

        scheduler.show(message: "Available", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(1)
        scheduler.invalidate()

        XCTAssertNil(state.editHint)
        XCTAssertFalse(state.editHintIsPositive)

        sleeper.resumeFirst()
        await drainTasks()
        XCTAssertNil(state.editHint)
        XCTAssertFalse(state.editHintIsPositive)
    }

    func testReleasedSchedulerDoesNotWriteBack() async {
        let state = KeyboardState()
        let sleeper = ControlledSleeper()
        var scheduler: EditHintScheduler? = makeScheduler(state: state, sleeper: sleeper)
        let schedulerReference = WeakSchedulerReference(scheduler)

        scheduler?.show(message: "Available", isPositive: true, duration: .seconds(10))
        await sleeper.waitForRequestCount(1)
        scheduler = nil

        XCTAssertNil(schedulerReference.value)

        sleeper.resumeFirst()
        await drainTasks()
        XCTAssertEqual(state.editHint, "Available")
        XCTAssertTrue(state.editHintIsPositive)
    }

    private func makeScheduler(
        state: KeyboardState,
        sleeper: ControlledSleeper
    ) -> EditHintScheduler {
        EditHintScheduler(
            state: state,
            sleeper: { duration in
                await sleeper.sleep(for: duration)
            }
        )
    }

    private func drainTasks() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}

@MainActor
private final class WeakSchedulerReference {
    weak var value: EditHintScheduler?

    init(_ value: EditHintScheduler?) {
        self.value = value
    }
}

@MainActor
private final class ControlledSleeper {
    private(set) var recordedDurations: [Duration] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for duration: Duration) async {
        recordedDurations.append(duration)
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while recordedDurations.count < count {
            await Task.yield()
        }
    }

    func resumeFirst() {
        guard !continuations.isEmpty else {
            XCTFail("Expected a pending sleep request")
            return
        }
        continuations.removeFirst().resume()
    }

    func resumeAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
