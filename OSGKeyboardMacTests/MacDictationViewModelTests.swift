// MacDictationViewModelTests.swift
// OSGKeyboard · Mac tests
//
// Regression coverage for cancelling an asynchronous recorder start.

import Foundation
import XCTest
@testable import OSGKeyboard

@MainActor
final class MacDictationViewModelTests: XCTestCase {

    func testCancellingButtonPreparationKeepsGateClosedUntilStartUnwinds() async {
        let suiteName = "com.osgkeyboard.mac.tests.prepare.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recorder = SuspendedMacAudioRecorder()
        let viewModel = MacDictationViewModel(
            defaults: defaults,
            recorder: recorder,
            startHotkeyService: false
        )

        viewModel.toggleRecording()
        let didStartPreparing = await waitUntil { recorder.isStartPending }
        XCTAssertTrue(didStartPreparing)
        XCTAssertTrue(viewModel.isPreparingToRecord)

        viewModel.toggleRecording()

        XCTAssertTrue(
            viewModel.isPreparingToRecord,
            "Cancellation must not reopen the start gate while recorder.start() is still unwinding."
        )
        recorder.completeStart()
        let didFinishCancelling = await waitUntil { !viewModel.isPreparingToRecord }
        XCTAssertTrue(didFinishCancelling)
        XCTAssertFalse(viewModel.isRecording)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertGreaterThanOrEqual(recorder.stopCallCount, 1)
    }

    private func waitUntil(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }
}

private final class SuspendedMacAudioRecorder: MacAudioRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, any Error>?
    private var stops = 0

    var isStartPending: Bool {
        lock.lock()
        defer { lock.unlock() }
        return startContinuation != nil
    }

    var stopCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return stops
    }

    func level() -> Float { 0 }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            startContinuation = continuation
            lock.unlock()
        }
    }

    func completeStart() {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    func makeSnapshotStream() -> AsyncStream<AudioBufferSnapshot> {
        AsyncStream { $0.finish() }
    }

    func stop() -> [Float] {
        lock.lock()
        stops += 1
        lock.unlock()
        return []
    }
}
