@testable import OSGKeyboardShared
import XCTest

final class FlowStartTransactionPolicyTests: XCTestCase {
    func testSameUtteranceIsIdempotentAcrossStartingRecordingAndProcessing() {
        let id = UUID()
        for state in [
            FlowHostUtteranceState.starting(id),
            .recording(id),
            .processing(id)
        ] {
            XCTAssertEqual(
                FlowStartTransactionPolicy.decide(
                    incomingUtteranceID: id,
                    deadlineAt: 200,
                    now: 100,
                    hostState: state
                ),
                .idempotent
            )
        }
    }

    func testDifferentUtteranceIsRejectedWhileBusy() {
        XCTAssertEqual(
            FlowStartTransactionPolicy.decide(
                incomingUtteranceID: UUID(),
                deadlineAt: 200,
                now: 100,
                hostState: .starting(UUID())
            ),
            .rejectBusy
        )
    }

    func testExpiredStartIsRejectedBeforeCapture() {
        XCTAssertEqual(
            FlowStartTransactionPolicy.decide(
                incomingUtteranceID: UUID(),
                deadlineAt: 100,
                now: 100,
                hostState: .idle
            ),
            .rejectExpired
        )
    }

    func testIdleStartWithinBudgetIsAccepted() {
        XCTAssertEqual(
            FlowStartTransactionPolicy.decide(
                incomingUtteranceID: UUID(),
                deadlineAt: 101,
                now: 100,
                hostState: .idle
            ),
            .accept
        )
    }

    func testEditAndDictationShareOneRequestContract() {
        let reference = EditableInputReference(
            historyEntryID: UUID(),
            historyEntryRevision: 3,
            displayText: "原文",
            insertedText: "原文",
            postInsertionFingerprint: "field",
            extensionInstanceID: UUID()
        )
        let edit = FlowUtteranceRequest.editLastInput(reference)
        XCTAssertEqual(edit.mode, .editLastInput)
        XCTAssertEqual(edit.editSourceText, "原文")
        XCTAssertEqual(edit.sourceHistoryEntryID, reference.historyEntryID)
        XCTAssertEqual(edit.sourceHistoryEntryRevision, 3)

        XCTAssertEqual(FlowUtteranceRequest.dictation.mode, .dictation)
        XCTAssertNil(FlowUtteranceRequest.dictation.editSourceText)
    }
}
