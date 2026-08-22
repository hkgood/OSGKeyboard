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
        // The current self-contained complaint model remains advisory until
        // its manually authored holdout precision reaches the release gate.
        XCTAssertFalse(complaint.complaint.isApprovedForAutomaticRouting)
        XCTAssertGreaterThan(complaint.complaint.confidence, 0)
    }

    func testPersonalPlanDoesNotBecomeAutomaticTask() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            "私人备忘：我准备周五自己整理完这份报告。"
        )

        XCTAssertTrue(analysis.task.isApprovedForAutomaticRouting)
        XCTAssertFalse(analysis.task.isDetected)
    }
}
