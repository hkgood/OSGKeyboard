// DictationBridgeTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class DictationBridgeTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.dictation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testStoreAndConsumeTranscript() {
        let defaults = makeDefaults()

        DictationBridge.storePendingTranscript(" hello ", defaults: defaults)
        let consumed = DictationBridge.consumePendingTranscript(defaults: defaults)

        XCTAssertEqual(consumed, "hello")
        XCTAssertNil(DictationBridge.consumePendingTranscript(defaults: defaults))
    }

    func testConsumeIgnoresExpiredTranscript() {
        let defaults = makeDefaults()
        DictationBridge.storePendingTranscript("stale", defaults: defaults)
        // maxAge = 1ms, then delay to force expiry
        usleep(2_000)
        let consumed = DictationBridge.consumePendingTranscript(maxAge: 0.001, defaults: defaults)
        XCTAssertNil(consumed)
    }

    func testStatusLifecycle() {
        let defaults = makeDefaults()

        DictationBridge.markRequested(defaults: defaults)
        XCTAssertEqual(DictationBridge.currentStatus(defaults: defaults).status, .requested)

        DictationBridge.setStatus(.recording, defaults: defaults)
        XCTAssertEqual(DictationBridge.currentStatus(defaults: defaults).status, .recording)

        DictationBridge.storePendingTranscript("ok", defaults: defaults)
        XCTAssertEqual(DictationBridge.currentStatus(defaults: defaults).status, .done)

        _ = DictationBridge.consumePendingTranscript(defaults: defaults)
        XCTAssertEqual(DictationBridge.currentStatus(defaults: defaults).status, .idle)
    }

    func testStatusMessageAndTimestamp() {
        let defaults = makeDefaults()
        DictationBridge.setStatus(.error, message: "fail", defaults: defaults)
        let snapshot = DictationBridge.currentStatus(defaults: defaults)
        XCTAssertEqual(snapshot.status, .error)
        XCTAssertEqual(snapshot.message, "fail")
        XCTAssertGreaterThan(snapshot.updatedAt, 0)
    }
}
