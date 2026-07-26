// FlowCommandPollerTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class FlowCommandPollerTests: XCTestCase {

    private func makeCommand(
        sessionId: UUID = UUID(),
        utteranceId: UUID = UUID(),
        seq: Int64 = 1,
        action: FlowCommand.Action = .startRecording
    ) -> FlowCommand {
        FlowCommand(
            sessionId: sessionId,
            utteranceId: utteranceId,
            commandSeq: seq,
            action: action,
            localeId: "auto"
        )
    }

    func testConsumeIfNewReturnsFirstCommand() {
        var poller = FlowCommandPoller()
        let command = makeCommand(seq: 10)
        XCTAssertEqual(poller.consumeIfNew(command), command)
    }

    func testConsumeIfNewDedupesIdenticalFingerprint() {
        var poller = FlowCommandPoller()
        let command = makeCommand(seq: 10)
        XCTAssertNotNil(poller.consumeIfNew(command))
        XCTAssertNil(poller.consumeIfNew(command))
    }

    func testConsumeIfNewClearsFingerprintWhenNil() {
        var poller = FlowCommandPoller()
        let command = makeCommand(seq: 10)
        _ = poller.consumeIfNew(command)
        _ = poller.consumeIfNew(nil)
        XCTAssertNotNil(poller.consumeIfNew(command))
    }

    func testValidateRejectsStaleSession() {
        let poller = FlowCommandPoller()
        let active = UUID()
        let command = makeCommand(sessionId: UUID(), seq: 5)
        XCTAssertEqual(
            poller.validate(command: command, activeSessionId: active),
            .staleSession
        )
    }

    func testValidateRejectsNonIncreasingSeq() {
        var poller = FlowCommandPoller()
        let sessionId = UUID()
        poller.markHandled(makeCommand(sessionId: sessionId, seq: 20))
        let command = makeCommand(sessionId: sessionId, seq: 15)
        XCTAssertEqual(
            poller.validate(command: command, activeSessionId: sessionId),
            .seqNotIncreasing
        )
    }

    func testValidateAcceptsIncreasingSeq() {
        var poller = FlowCommandPoller()
        let sessionId = UUID()
        poller.markHandled(makeCommand(sessionId: sessionId, seq: 20))
        let command = makeCommand(sessionId: sessionId, seq: 21)
        XCTAssertNil(poller.validate(command: command, activeSessionId: sessionId))
    }

    func testResetClearsSeqAndFingerprint() {
        var poller = FlowCommandPoller()
        let sessionId = UUID()
        poller.markHandled(makeCommand(sessionId: sessionId, seq: 99))
        poller.reset()
        XCTAssertEqual(poller.lastHandledCommandSeq, 0)
        XCTAssertNotNil(poller.consumeIfNew(makeCommand(sessionId: sessionId, seq: 100)))
    }
}
