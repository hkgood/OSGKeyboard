// FlowResultDeliveryTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowResultDeliveryTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.delivery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testWritePartialSkipsEmptyText() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writePartial(
            text: "   ",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 1,
            defaults: defaults
        )
        XCTAssertNil(FlowSessionBridge.latestResult(defaults: defaults))
    }

    func testWriteFinalRoundTrip() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writeFinal(
            text: "hello world",
            warning: "polish skipped",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 7,
            defaults: defaults
        )
        let result = FlowSessionBridge.latestResult(defaults: defaults)
        XCTAssertEqual(result?.status, .final)
        XCTAssertEqual(result?.text, "hello world")
        XCTAssertEqual(result?.warning, "polish skipped")
        XCTAssertEqual(result?.commandSeq, 7)
    }

    func testWriteErrorIncludesKind() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        FlowResultDelivery.writeError(
            message: "no speech",
            kind: .noSpeech,
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 3,
            defaults: defaults
        )
        let result = FlowSessionBridge.latestResult(defaults: defaults)
        XCTAssertEqual(result?.status, .error)
        XCTAssertEqual(result?.errorKind, .noSpeech)
        XCTAssertEqual(result?.text, "no speech")
    }

    func testCommandToResultIntegration() {
        let defaults = makeDefaults()
        let sessionId = UUID()
        let utteranceId = UUID()
        var poller = FlowCommandPoller()

        let command = FlowCommand(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: 100,
            action: .stopRecording,
            localeId: "auto"
        )
        FlowSessionBridge.markSessionActive(duration: 60, sessionId: sessionId, defaults: defaults)
        FlowSessionBridge.writeCommand(command, defaults: defaults)

        guard let polled = poller.consumeIfNew(FlowSessionBridge.latestCommand(defaults: defaults)) else {
            return XCTFail("expected command")
        }
        XCTAssertNil(poller.validate(command: polled, activeSessionId: sessionId))
        poller.markHandled(polled)

        FlowResultDelivery.writeFinal(
            text: "dictated text",
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: polled.commandSeq,
            defaults: defaults
        )

        let matched = KeyboardFlowResultMatcher.matchingResult(
            latest: FlowSessionBridge.latestResult(defaults: defaults),
            activeSessionId: sessionId,
            currentUtteranceId: utteranceId
        )
        XCTAssertTrue(KeyboardFlowResultMatcher.isConsumableFinal(matched!))
    }
}
