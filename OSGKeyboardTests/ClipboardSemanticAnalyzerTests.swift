// ClipboardSemanticAnalyzerTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class ClipboardSemanticAnalyzerTests: XCTestCase {
    func testEmptyTextReturnsNoLabels() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(" \n ")

        XCTAssertNil(analysis.language)
        XCTAssertEqual(analysis.sentiment, .unknown)
        XCTAssertFalse(analysis.task.isDetected)
        XCTAssertFalse(analysis.question.isDetected)
        XCTAssertFalse(analysis.invitation.isDetected)
        XCTAssertFalse(analysis.complaint.isDetected)
        XCTAssertFalse(analysis.replyableMessage.isDetected)
    }

    func testDetectsLanguageAndStructuredDataLocally() async {
        let text = """
        Meet on August 28, 2026 at 3:00 PM at 1 Apple Park Way, Cupertino, CA 95014.
        Call +1 408-996-1010 or visit https://www.apple.com.
        """

        let analysis = await ClipboardSemanticAnalyzer().analyze(text)

        XCTAssertEqual(analysis.language?.identifier, "en")
        XCTAssertTrue(analysis.hasDateOrTime)
        XCTAssertTrue(analysis.hasAddress)
        XCTAssertTrue(analysis.hasPhoneNumber)
        XCTAssertTrue(analysis.hasURL)
    }

    func testStandaloneHTTPSLinkBecomesSingleWebURL() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            "https://www.apple.com/newsroom/"
        )

        XCTAssertEqual(
            analysis.singleWebURL?.absoluteString,
            "https://www.apple.com/newsroom/"
        )
    }

    func testBareDomainIsNormalizedToHTTPS() {
        let url = ClipboardWebLinkResolver.singleWebURL(
            in: "详情见 www.apple.com/newsroom/"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://www.apple.com/newsroom/"
        )
    }

    func testMultipleLinksHaveNoSingleActionTarget() {
        XCTAssertNil(
            ClipboardWebLinkResolver.singleWebURL(
                in: "https://example.com/a 和 https://example.com/b"
            )
        )
    }

    func testStandalonePhoneNumberBecomesSingleActionTarget() async throws {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            "请拨打 +1 (408) 996-1010"
        )

        XCTAssertEqual(analysis.singlePhoneNumber, "+14089961010")
        XCTAssertEqual(
            AIPhoneNumberResolver.telephoneURL(
                for: try XCTUnwrap(analysis.singlePhoneNumber)
            )?.absoluteString,
            "tel:+14089961010"
        )
    }

    func testMultiplePhoneNumbersHaveNoSingleActionTarget() {
        let labels = [
            ClipboardTextLabel(sourceText: "+1 408-996-1010"),
            ClipboardTextLabel(sourceText: "400-666-8800")
        ]
        XCTAssertNil(AIPhoneNumberResolver.singlePhoneNumber(from: labels))
    }

    func testApprovedModelsDetectHighConfidenceIntents() async {
        let analyzer = ClipboardSemanticAnalyzer()

        let task = await analyzer.analyze(
            "请今天下班前发送会议纪要，完成后发给项目群。"
        )
        let question = await analyzer.analyze(
            "退款流程具体是怎么安排的？"
        )
        let invitation = await analyzer.analyze(
            "今晚七点在老地方吃饭，你能来吗？"
        )
        let complaint = await analyzer.analyze(
            "应用一直闪退，数据还丢了，你们能尽快处理吗？"
        )

        XCTAssertTrue(task.task.isApprovedForAutomaticRouting)
        XCTAssertTrue(task.task.isDetected)
        XCTAssertTrue(question.question.isApprovedForAutomaticRouting)
        XCTAssertTrue(question.question.isDetected)
        XCTAssertTrue(invitation.invitation.isApprovedForAutomaticRouting)
        XCTAssertTrue(invitation.invitation.isDetected)
        XCTAssertTrue(complaint.complaint.isApprovedForAutomaticRouting)
        XCTAssertTrue(complaint.complaint.isDetected)
    }

    func testReplyableModelDistinguishesConversationFromAcknowledgment() async {
        let analyzer = ClipboardSemanticAnalyzer()

        let conversation = await analyzer.analyze(
            "我刚到家，今天真是累坏了。"
        )
        let acknowledgment = await analyzer.analyze(
            "收到，谢谢。"
        )

        XCTAssertTrue(conversation.replyableMessage.isApprovedForAutomaticRouting)
        XCTAssertTrue(conversation.replyableMessage.isDetected)
        XCTAssertTrue(acknowledgment.replyableMessage.isApprovedForAutomaticRouting)
        XCTAssertFalse(acknowledgment.replyableMessage.isDetected)
    }

    /// The classifiers are trained on single sentences. A multi-sentence paste
    /// analyzed as one blob dilutes bag-of-words confidence below the routing
    /// threshold, so the intent must be scored per sentence instead.
    func testIntentIsFoundInsideAMultiSentencePaste() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            """
            各位好，这是本周的进度同步。设计稿已经全部定稿，开发那边也开始联调了。\
            麻烦你今天下班前把新版报价单发我。另外测试环境这两天可能会有波动，\
            大家注意一下。
            """
        )

        XCTAssertTrue(analysis.task.isDetected)
    }

    func testPersonalPlanDoesNotBecomeAutomaticTask() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            "私人备忘：我准备周五自己整理完这份报告。"
        )

        XCTAssertTrue(analysis.task.isApprovedForAutomaticRouting)
        XCTAssertFalse(analysis.task.isDetected)
        XCTAssertFalse(analysis.replyableMessage.isDetected)
    }
}
