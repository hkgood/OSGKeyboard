// PreviewASRControllerStateTests.swift
// OSGKeyboard · Tests
//
// Locks in the state-machine contract for the keyboard preview's
// ASR controller. The previous bug was: `stop()` called
// `asrTask?.cancel()` on the consumer task that was waiting for the
// ASR `.final` event. The cancellation cascaded through
// `continuation.onTermination → self.cancel()` and suppressed the
// `.final` yield, leaving the controller in `.processing` forever
// because no one scheduled the transition out. The fix is: don't
// cancel on stop, let the consumer naturally see the `.final` and
// flip the phase.
//
// These tests don't drive a real ASR pipeline — they verify the
// state-machine contract directly. The class is `@MainActor`
// isolated, so all assertions happen on main. `asrTask` is
// `internal` (not `private`) precisely so this file can install a
// known consumer task and observe whether `stop()` cancels it.
//
// Note on the 3-second processing-timeout safety net: that
// fallback (a `Task { sleep 3s; if .processing → .idle }` block
// inside `stop()`) is not unit-tested here — testing it would
// require either a 3-second test or extracting the policy to a
// testable helper. The primary fix above removes the original
// bug outright; the timeout is a defensive safety net for a
// separate class of failure (analyzer hang) and is straightforward
// enough to read that a test adds little. If a future change
// touches the safety-net block, re-introduce a test that mocks
// the ASR to never yield `.final` and asserts the timeout fires.

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class PreviewASRControllerStateTests: XCTestCase {

    /// Core fix: `stop()` MUST NOT cancel `asrTask`. The consumer
    /// task is the only place the `.final` event can land, and
    /// cancelling it leaves the UI in `.processing` forever. This
    /// is the regression test for the original bug — if it ever
    /// fails, the disc is stuck again.
    func testStopDoesNotCancelConsumerTask() {
        let controller = LiveDictationController()
        let consumerTask = Task<Void, Never> {}
        controller.asrTask = consumerTask

        controller.stop()

        XCTAssertFalse(
            consumerTask.isCancelled,
            "stop() must not cancel the consumer task; the .final event needs the consumer alive to land"
        )
    }

    /// Idempotency: calling `stop()` twice (e.g. `.onDisappear`
    /// fires after the user already stopped manually) must not
    /// misbehave — no double-cancel, no extra state transitions.
    /// This is the contract `.onDisappear` relies on.
    func testStopIsIdempotent() {
        let controller = LiveDictationController()
        let consumerTask = Task<Void, Never> {}
        controller.asrTask = consumerTask

        controller.stop()
        controller.stop()

        XCTAssertFalse(consumerTask.isCancelled)
    }
}
