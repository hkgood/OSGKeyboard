// PolishPromptComposerQuestionTests.swift
// OSGKeyboard · Tests

import XCTest
@testable import OSGKeyboardShared

final class PolishPromptComposerQuestionTests: XCTestCase {

    func testPracticalQuestionDraftReceivesGuard() {
        let prompt = compose(text: "你觉得这个包怎么样", styleID: "builtin.light")

        XCTAssertTrue(prompt.contains("问句守卫"))
        XCTAssertTrue(prompt.contains("同一个人提出的同一个问句"))
    }

    func testStatementDraftDoesNotReceiveGuard() {
        XCTAssertFalse(
            compose(
                text: "这款防晒霜我用了不油",
                styleID: "builtin.light"
            ).contains("问句守卫")
        )
    }

    func testOpponentQuoteDoesNotReceiveQuestionGuard() {
        XCTAssertFalse(
            PolishPromptComposer.shouldPreserveQuestion(
                "回他别老说大家都觉得你点名是谁"
            )
        )
    }

    func testQuestionDetectionSupportsNaturalPatterns() {
        let questions = [
            "今晚有空吗",
            "你觉得这个方案怎么样",
            "我们什么时候见面",
            "要不要一起吃饭",
            "还有哪些 issue？",
        ]

        for text in questions {
            XCTAssertTrue(PolishPromptComposer.shouldPreserveQuestion(text), text)
        }
    }

    func testPracticalComposerUsesFullCoreInsteadOfLegacyRoutingBlocks() {
        let prompt = compose(text: "你觉得这个包怎么样", styleID: "builtin.light")

        XCTAssertTrue(prompt.contains("全局输出契约"))
        XCTAssertTrue(prompt.contains("不回答、评价、附和"))
        XCTAssertFalse(prompt.contains("信息不足时的硬刹车"))
        XCTAssertFalse(prompt.contains("本次模式：保守清理"))
    }

    func testHeavyFunComposerDoesNotReceivePracticalQuestionGuard() {
        let prompt = compose(
            text: "你觉得这个包怎么样",
            styleID: "builtin.dating",
            intensity: .heavy
        )

        XCTAssertTrue(prompt.contains("趣味风格共享格式化"))
        XCTAssertFalse(prompt.contains("全局输出契约"))
        XCTAssertFalse(prompt.contains("问句守卫"))
    }

    func testLightFunComposerReceivesPracticalQuestionGuard() {
        let prompt = compose(
            text: "你觉得这个包怎么样",
            styleID: "builtin.dating",
            intensity: .light
        )

        XCTAssertTrue(prompt.contains("全局输出契约"))
        XCTAssertTrue(prompt.contains("问句守卫"))
        XCTAssertFalse(prompt.contains("趣味风格共享格式化"))
    }

    func testFunStylesDoNotSkipUltraShortLLM() {
        let ids = [
            "builtin.dating",
            "builtin.flex",
            "builtin.corp",
            "builtin.diba",
            "builtin.xhs",
        ]

        for id in ids {
            XCTAssertFalse(
                TranscriptPostProcessor.shouldSkipLLM(
                    for: "还行吧",
                    styleID: id
                ),
                id
            )
        }
    }

    private func compose(
        text: String,
        styleID: String,
        intensity: PolishIntensity = .default
    ) -> String {
        let style = PolishStylePackCatalog.resolve(
            id: styleID,
            userCatalog: .empty
        )
        return PolishPromptComposer.compose(
            text: text,
            style: style,
            context: PolishContext(),
            dictionaryBlock: "",
            intensity: intensity,
            useChineseGuidance: true
        )
    }
}
