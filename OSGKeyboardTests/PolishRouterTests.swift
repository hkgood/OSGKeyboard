// PolishRouterTests.swift
// OSGKeyboard · Tests
//
// Locks ABE routing: sparse gate (A), prompt hard-brakes (B), and
// style-specific degradation (E) without calling a real LLM.

import XCTest
@testable import OSGKeyboardShared

final class PolishRouterTests: XCTestCase {

    func testSparseShortForcesConservativeLightForFunStyles() {
        let decision = PolishRouter.decide(
            text: "这个还行吧",
            styleID: "builtin.xhs",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .conservative)
        XCTAssertEqual(decision.effectiveIntensity, .light)
        XCTAssertEqual(decision.effectiveStyleID, "builtin.xhs")
        XCTAssertTrue(decision.reasons.contains("A:sparse"))
    }

    func testDibaWithoutOpponentFallsBackToChat() {
        let decision = PolishRouter.decide(
            text: "不是这样的",
            styleID: "builtin.diba",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .chatFallback)
        XCTAssertEqual(decision.effectiveStyleID, "builtin.chat")
        XCTAssertEqual(decision.effectiveIntensity, .light)
        XCTAssertTrue(decision.reasons.contains("E:diba_no_opponent"))
    }

    func testDibaWithOpponentQuoteStaysFull() {
        let decision = PolishRouter.decide(
            text: "回他你这叫为你好那对方不同意你还要强行是吧",
            styleID: "builtin.diba",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .full)
        XCTAssertEqual(decision.effectiveStyleID, "builtin.diba")
        XCTAssertEqual(decision.effectiveIntensity, .heavy)
    }

    func testDatingSparseForcesConservative() {
        let decision = PolishRouter.decide(
            text: "还行吧",
            styleID: "builtin.dating",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .conservative)
        XCTAssertEqual(decision.effectiveIntensity, .light)
        XCTAssertTrue(decision.reasons.contains("E:dating_short_no_flirt"))
    }

    func testDatingInviteQuestionStaysFull() {
        let decision = PolishRouter.decide(
            text: "今晚有空吗",
            styleID: "builtin.dating",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .full)
        XCTAssertEqual(decision.effectiveIntensity, .heavy)
    }

    func testChatSparseForcesConservativeNoReply() {
        let decision = PolishRouter.decide(
            text: "没事",
            styleID: "builtin.chat",
            intensity: .medium
        )
        XCTAssertEqual(decision.mode, .conservative)
        XCTAssertEqual(decision.effectiveIntensity, .light)
        XCTAssertTrue(decision.reasons.contains("E:chat_no_reply"))
    }

    func testFormalKeepsFullEvenWhenShort() {
        let decision = PolishRouter.decide(
            text: "收到",
            styleID: "builtin.formal",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .full)
        XCTAssertEqual(decision.effectiveIntensity, .heavy)
    }

    func testContentfulMediumStaysFullForXHS() {
        let decision = PolishRouter.decide(
            text: "这款防晒霜我用了不油夏天可以推荐",
            styleID: "builtin.xhs",
            intensity: .heavy
        )
        XCTAssertEqual(decision.mode, .full)
        XCTAssertEqual(decision.effectiveIntensity, .heavy)
    }

    func testPromptBlockIncludesHardBrakeForFunStyles() {
        let block = PolishRouter.promptBlock(
            mode: .conservative,
            styleID: "builtin.xhs",
            useChineseGuidance: true
        )
        XCTAssertTrue(block.contains("信息不足时的硬刹车"))
        XCTAssertTrue(block.contains("本次模式：保守清理"))
        XCTAssertTrue(block.contains("小红书专属降级"))
    }

    func testComposerInjectsRoutingBlock() {
        let style = PolishStylePackCatalog.resolve(
            id: "builtin.dating",
            userCatalog: .empty
        )
        let prompt = PolishPromptComposer.compose(
            text: "还行",
            style: style,
            context: PolishContext(intensity: .light),
            dictionaryBlock: "",
            globalContract: "GLOBAL",
            useChineseGuidance: true,
            routingMode: .conservative
        )
        XCTAssertTrue(prompt.contains("信息不足时的硬刹车"))
        XCTAssertTrue(prompt.contains("直男癌专属降级"))
        XCTAssertTrue(prompt.contains("本次模式：保守清理"))
    }

    func testIsInformationSparseDetectsHollowShorts() {
        XCTAssertTrue(PolishRouter.isInformationSparse("香香的"))
        XCTAssertTrue(PolishRouter.isInformationSparse("这个还行吧"))
        XCTAssertFalse(PolishRouter.isInformationSparse(
            "这款防晒霜我用了不油夏天可以推荐"
        ))
    }
}
