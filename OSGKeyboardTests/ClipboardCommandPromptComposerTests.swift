// ClipboardCommandPromptComposerTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class ClipboardCommandPromptComposerTests: XCTestCase {

    func testUserMessageIncludesMaterialInstructionAndPrevious() {
        let input = ClipboardCommandPromptComposer.Input(
            snapshot: "对方说周末见面",
            instruction: "委婉拒绝",
            previousOutput: "这周不太方便"
        )
        let user = ClipboardCommandPromptComposer.userMessage(input, language: .chinese)
        XCTAssertTrue(user.contains("【材料】"))
        XCTAssertTrue(user.contains("对方说周末见面"))
        XCTAssertTrue(user.contains("【指令】"))
        XCTAssertTrue(user.contains("委婉拒绝"))
        XCTAssertTrue(user.contains("【上一版结果】"))
        XCTAssertTrue(user.contains("这周不太方便"))
    }

    func testSystemPromptDoesNotEmbedR6DictationBan() {
        let system = ClipboardCommandPromptComposer.compose(
            .init(snapshot: "材料", instruction: "总结"),
            language: .chinese
        )
        XCTAssertTrue(system.contains("剪贴板写作助手"))
        XCTAssertFalse(system.contains("不是向你提出的问题或命令"))
    }

    func testFailureLocalizationKeysAreStable() {
        XCTAssertEqual(
            ClipboardCommandFailure.pasteDenied.localizationKey,
            "keyboard.clipboard.reject.pasteDenied"
        )
        XCTAssertEqual(
            ClipboardCommandFailure.material(.tooShort).localizationKey,
            "keyboard.clipboard.reject.tooShort"
        )
        XCTAssertEqual(
            ClipboardCommandFailure.secureField.localizationKey,
            "keyboard.clipboard.reject.secureField"
        )
        XCTAssertEqual(
            ClipboardCommandFailure.prepareFailed.localizationKey,
            "keyboard.clipboard.reject.prepareFailed"
        )
    }
}
