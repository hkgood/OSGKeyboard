// AIClipboardPromptTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class AIClipboardPromptTests: XCTestCase {
    func testInternalClipboardEnvelopeIsDetected() {
        let prompt = AIClipboardPrompt.compose(
            instruction: "请翻译剪贴板",
            material: "hello"
        )
        XCTAssertTrue(AIClipboardPrompt.isInternalPrompt(prompt))
        XCTAssertFalse(AIClipboardPrompt.isInternalPrompt("请翻译剪贴板"))
    }

    func testComposeKeepsInstructionAndMaterialInSeparateBlocks() {
        let prompt = AIClipboardPrompt.compose(
            instruction: "请翻译剪贴板",
            material: "会议改到 <A 栋>"
        )
        XCTAssertTrue(prompt.contains("<instruction>"))
        XCTAssertTrue(prompt.contains("<clipboard_text>"))
        XCTAssertTrue(prompt.contains("请翻译剪贴板"))
        // Untrusted material can never open its own tags.
        XCTAssertTrue(prompt.contains("&lt;A 栋&gt;"))
        XCTAssertFalse(prompt.contains("<A 栋>"))
    }

    func testResolveFailsClosedWithoutMaterial() {
        XCTAssertEqual(
            AIClipboardPrompt.resolve(instruction: "请翻译剪贴板", material: nil),
            .materialUnavailable
        )
        XCTAssertEqual(
            AIClipboardPrompt.resolve(instruction: "请翻译剪贴板", material: "   "),
            .materialUnavailable
        )
    }

    func testSpokenQuestionWithoutClipboardIntentPassesThrough() {
        XCTAssertEqual(
            AIClipboardPrompt.resolveSpoken(question: "明天上海天气如何", material: "机密内容"),
            .ready("明天上海天气如何")
        )
    }

    func testSpokenClipboardIntentAttachesMaterial() throws {
        let resolution = AIClipboardPrompt.resolveSpoken(
            question: "帮我回复剪贴板里的这条消息",
            material: "周五下午两点可以吗？"
        )
        guard case .ready(let prompt) = resolution else {
            return XCTFail("expected a composed prompt")
        }
        XCTAssertTrue(prompt.contains("周五下午两点可以吗？"))
        XCTAssertTrue(prompt.contains("clipboard_request"))
    }

    func testSpokenClipboardIntentFailsClosedWhenHistoryIsEmpty() {
        XCTAssertEqual(
            AIClipboardPrompt.resolveSpoken(question: "translate my clipboard", material: nil),
            .materialUnavailable
        )
    }

    func testClipboardCardFailsClosedAfterEligibilityWindow() {
        let card = AIHintLocalCatalog.cards(locale: "zh")
            .first { $0.requiresClipboard30s }!
        XCTAssertEqual(
            AIHintPool.resolvePrompt(for: card, clipboardText: nil),
            .materialUnavailable
        )
    }

    func testNonClipboardCardDropsLegacyPlaceholder() throws {
        let card = AIHintCard(
            id: "remote-1",
            displayText: "聊聊热点",
            prompt: "请概括今日热点 \(AIClipboardPrompt.materialPlaceholder)",
            category: "society"
        )
        guard case .ready(let prompt) = AIHintPool.resolvePrompt(
            for: card,
            clipboardText: "无关内容"
        ) else {
            return XCTFail("expected a ready prompt")
        }
        XCTAssertEqual(prompt, "请概括今日热点")
        XCTAssertFalse(prompt.contains("无关内容"))
    }
}
