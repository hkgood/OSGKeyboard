// MacAudioRecorderSnapshotStreamTests.swift
// OSGKeyboard · Mac tests
//
// Regression guard for the freeze that hit when the hold-to-talk key was
// released. `MacAudioRecorder` finished its snapshot continuation while holding
// a non-reentrant `NSLock`; `AsyncStream.Continuation.finish()` invokes
// `onTermination` synchronously on the calling thread, that handler re-took the
// same lock, and because the release path runs `stop()` on the main actor the
// whole app wedged.

import XCTest
@testable import OSGKeyboard

final class MacAudioRecorderSnapshotStreamTests: XCTestCase {

    /// Installing a second stream finishes the first one. Run off-main and
    /// bounded by a semaphore timeout so a reintroduced lock re-entry fails the
    /// test instead of hanging the whole suite.
    func testReplacingSnapshotStreamDoesNotDeadlock() {
        let recorder = MacAudioRecorder()
        let firstStream = recorder.makeSnapshotStream()
        let drain = Task { for await _ in firstStream {} }

        let installed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            _ = recorder.makeSnapshotStream()
            installed.signal()
        }

        XCTAssertEqual(
            installed.wait(timeout: .now() + 2),
            .success,
            "Replacing the snapshot stream deadlocked: finish() ran while holding the recorder lock."
        )
        drain.cancel()
    }

    /// The outgoing stream's termination handler fires *during* the install of
    /// its replacement, so it must recognise itself as stale and leave the new
    /// sink attached — otherwise live ASR silently receives no audio.
    func testReplacingSnapshotStreamKeepsTheNewSinkAttached() {
        let recorder = MacAudioRecorder()
        let firstStream = recorder.makeSnapshotStream()
        let drain = Task { for await _ in firstStream {} }

        let secondStream = recorder.makeSnapshotStream()

        XCTAssertTrue(
            recorder.hasLiveSnapshotSink,
            "The replaced stream's termination detached the sink that had just replaced it."
        )
        // The sink lives only as long as the stream: releasing `secondStream`
        // early would terminate it and invalidate the assertion above.
        withExtendedLifetime(secondStream) {}
        drain.cancel()
    }
}
