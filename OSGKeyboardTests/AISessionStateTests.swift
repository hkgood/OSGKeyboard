@testable import OSGKeyboardShared
import XCTest

final class AISessionStateTests: XCTestCase {
    func testSuccessfulAnswerReplacesPreviousOnlyAtTerminalResult() throws {
        var state = AISessionState()
        let conversationID = UUID()
        let firstUtteranceID = UUID()
        state.enter(conversationID: conversationID)
        state.beginPreparing(utteranceID: firstUtteranceID)
        state.beginListening(utteranceID: firstUtteranceID)
        state.beginRecognizing(utteranceID: firstUtteranceID)
        state.beginGenerating(question: "问题一", utteranceID: firstUtteranceID)
        state.receiveAnswer("答案一", utteranceID: firstUtteranceID)

        let secondUtteranceID = UUID()
        state.beginPreparing(utteranceID: secondUtteranceID)
        XCTAssertEqual(state.answer?.text, "答案一")

        state.beginListening(utteranceID: secondUtteranceID)
        state.beginGenerating(question: "问题二", utteranceID: secondUtteranceID)
        XCTAssertEqual(state.answer?.text, "答案一")

        state.receiveAnswer("答案二", utteranceID: secondUtteranceID)
        XCTAssertEqual(state.answer?.text, "答案二")
        XCTAssertTrue(state.canInsert)
    }

    func testCancellationRestoresPreviousAnswerState() {
        var state = AISessionState()
        let firstUtteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: firstUtteranceID)
        state.beginListening(utteranceID: firstUtteranceID)
        state.receiveAnswer("可用答案", utteranceID: firstUtteranceID)

        let secondUtteranceID = UUID()
        state.beginPreparing(utteranceID: secondUtteranceID)
        state.updateTranscript("未完成问题", utteranceID: secondUtteranceID)
        state.cancelCurrentWork()

        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.answer?.text, "可用答案")
        XCTAssertEqual(state.transcript, "")
    }

    func testAnswerRequiresInsertBeforeSend() {
        var state = AISessionState()
        let utteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: utteranceID)
        state.receiveAnswer("答案", utteranceID: utteranceID)

        XCTAssertTrue(state.canInsert)
        XCTAssertFalse(state.canSend)

        state.markAnswerInserted(offersSend: true)

        XCTAssertEqual(state.phase, .awaitingSend)
        XCTAssertFalse(state.canInsert)
        XCTAssertTrue(state.canSend)
        XCTAssertEqual(state.answer?.isInserted, true)

        state.markAnswerSent()

        XCTAssertEqual(state.phase, .sent)
        XCTAssertFalse(state.canSend)
        XCTAssertEqual(state.answer?.isSent, true)
    }

    func testNonSendFieldFinishesAfterInsertion() {
        var state = AISessionState()
        let utteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: utteranceID)
        state.receiveAnswer("答案", utteranceID: utteranceID)

        state.markAnswerInserted(offersSend: false)

        XCTAssertEqual(state.phase, .inserted)
        XCTAssertFalse(state.canPerformAnswerAction)
        XCTAssertEqual(state.answer?.isInserted, true)
        XCTAssertEqual(state.answer?.isSent, false)
    }

    func testDiscardReadyAnswerKeepsConversationActive() {
        var state = AISessionState()
        let conversationID = UUID()
        let utteranceID = UUID()
        state.enter(conversationID: conversationID)
        state.beginPreparing(utteranceID: utteranceID)
        state.receiveAnswer("光标变化后保留的回答", utteranceID: utteranceID)

        state.discardReadyAnswer()

        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.conversationID, conversationID)
        XCTAssertNil(state.answer)
        XCTAssertFalse(state.canInsert)
    }

    func testCancellationRestoresPendingSendState() {
        var state = AISessionState()
        let firstUtteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: firstUtteranceID)
        state.receiveAnswer("已插入答案", utteranceID: firstUtteranceID)
        state.markAnswerInserted(offersSend: true)

        let secondUtteranceID = UUID()
        state.beginPreparing(utteranceID: secondUtteranceID)
        state.cancelCurrentWork()

        XCTAssertEqual(state.phase, .awaitingSend)
        XCTAssertTrue(state.canSend)
    }

    func testStaleResultCannotReplaceCurrentAnswer() {
        var state = AISessionState()
        let currentUtteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: currentUtteranceID)

        state.receiveAnswer("迟到答案", utteranceID: UUID())

        XCTAssertNil(state.answer)
        XCTAssertEqual(state.phase, .preparing)
    }

    func testPartialAnswerKeepsPreviousCommittedAnswerUntilFinal() {
        var state = AISessionState()
        let firstUtteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: firstUtteranceID)
        state.receiveAnswer("答案一", utteranceID: firstUtteranceID)

        let secondUtteranceID = UUID()
        state.beginPreparing(utteranceID: secondUtteranceID)
        state.beginGenerating(question: "问题二", utteranceID: secondUtteranceID)
        state.receivePartialAnswer("草", utteranceID: secondUtteranceID)

        XCTAssertEqual(state.phase, .generating)
        XCTAssertEqual(state.draftAnswerText, "草")
        XCTAssertEqual(state.answer?.text, "答案一")
        XCTAssertFalse(state.canInsert)

        state.receivePartialAnswer("草稿答案", utteranceID: secondUtteranceID)
        XCTAssertEqual(state.draftAnswerText, "草稿答案")

        state.receiveAnswer("答案二", utteranceID: secondUtteranceID)
        XCTAssertNil(state.draftAnswerText)
        XCTAssertEqual(state.answer?.text, "答案二")
        XCTAssertTrue(state.canInsert)
    }

    func testCancelClearsDraftAndRestoresPreviousAnswer() {
        var state = AISessionState()
        let firstUtteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: firstUtteranceID)
        state.receiveAnswer("可用答案", utteranceID: firstUtteranceID)

        let secondUtteranceID = UUID()
        state.beginPreparing(utteranceID: secondUtteranceID)
        state.beginGenerating(question: "新问题", utteranceID: secondUtteranceID)
        state.receivePartialAnswer("半截", utteranceID: secondUtteranceID)
        state.cancelCurrentWork()

        XCTAssertNil(state.draftAnswerText)
        XCTAssertEqual(state.phase, .ready)
        XCTAssertEqual(state.answer?.text, "可用答案")
    }

    func testReplyVariantsBecomeReadyWithoutCreatingInsertableAnswer() {
        var state = AISessionState()
        let utteranceID = UUID()
        let variants = makeReplyVariants()
        state.enter()
        state.beginPreparing(utteranceID: utteranceID)

        state.receiveReplyVariants(variants, utteranceID: utteranceID)

        XCTAssertEqual(state.phase, .ready)
        XCTAssertTrue(state.canSelectReplyVariant)
        XCTAssertFalse(state.canInsert)
        XCTAssertNil(state.answer)
        XCTAssertEqual(state.replyVariants.map(\.kind), [.ordinary, .formal, .playful])
    }

    func testSelectingReplyVariantExposesSelectionForInsertionAndFeedback() throws {
        var state = AISessionState()
        let utteranceID = UUID()
        let variants = makeReplyVariants()
        state.enter()
        state.beginPreparing(utteranceID: utteranceID)
        state.receiveReplyVariants(variants, utteranceID: utteranceID)

        let answer = try XCTUnwrap(
            state.selectReplyVariant(id: variants[2].id)
        )

        XCTAssertEqual(answer.id, variants[2].id)
        XCTAssertEqual(answer.text, "轻松回复 🎉")
        XCTAssertEqual(state.selectedReplyVariant, variants[2])
        XCTAssertTrue(state.canInsert)
        XCTAssertFalse(state.canSelectReplyVariant)

        state.markAnswerInserted(offersSend: false)
        XCTAssertEqual(state.phase, .inserted)
    }

    func testDiscardReplyVariantsClearsAllCandidateState() {
        var state = AISessionState()
        let utteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: utteranceID)
        state.receiveReplyVariants(makeReplyVariants(), utteranceID: utteranceID)

        state.discardReadyAnswer()

        XCTAssertEqual(state.phase, .idle)
        XCTAssertTrue(state.replyVariants.isEmpty)
        XCTAssertNil(state.selectedReplyVariant)
    }

    func testSceneReplyVariantsUseLocalRoleOrder() {
        var state = AISessionState()
        let utteranceID = UUID()
        state.enter()
        state.beginPreparing(utteranceID: utteranceID)
        state.receiveReplyVariants(
            [
                AIReplyVariant(
                    kind: .invitationTentative,
                    emotion: .neutral,
                    text: "我确认一下。"
                ),
                AIReplyVariant(
                    kind: .invitationDecline,
                    emotion: .grateful,
                    text: "这次先不去了。"
                ),
                AIReplyVariant(
                    kind: .invitationAccept,
                    emotion: .warm,
                    text: "好呀，到时见。"
                )
            ],
            utteranceID: utteranceID
        )

        XCTAssertTrue(state.canSelectReplyVariant)
        XCTAssertEqual(
            state.replyVariants.map(\.kind),
            AIReplyVariantSet.invitation.kinds
        )
    }

    private func makeReplyVariants() -> [AIReplyVariant] {
        [
            AIReplyVariant(kind: .ordinary, emotion: .warm, text: "普通回复"),
            AIReplyVariant(kind: .formal, emotion: .neutral, text: "正式回复"),
            AIReplyVariant(kind: .playful, emotion: .celebratory, text: "轻松回复 🎉")
        ]
    }
}
