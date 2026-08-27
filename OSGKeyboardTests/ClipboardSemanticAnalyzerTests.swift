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
        XCTAssertFalse(analysis.scheduleNegotiation.isDetected)
        XCTAssertFalse(analysis.confirmationDecision.isDetected)
        XCTAssertFalse(analysis.followUpReminder.isDetected)
        XCTAssertFalse(analysis.blessing.isDetected)
    }

    func testComplaintTaskPolicySuppressesImplicitFailure() {
        XCTAssertTrue(
            ClipboardSemanticAnalyzer.shouldSuppressTask(
                text: "The same failure happened again and delivery is delayed.",
                complaintConfidence: 0.76
            )
        )
    }

    func testComplaintTaskPolicyPreservesExplicitAssignment() {
        XCTAssertFalse(
            ClipboardSemanticAnalyzer.shouldSuppressTask(
                text: "The attachment still fails. Please send the corrected file today.",
                complaintConfidence: 0.92
            )
        )
    }

    func testComplaintTaskPolicyIgnoresWeakComplaintEvidence() {
        XCTAssertFalse(
            ClipboardSemanticAnalyzer.shouldSuppressTask(
                text: "Delivery is delayed.",
                complaintConfidence: 0.59
            )
        )
    }

    func testImplicitComplaintDoesNotRouteAsTask() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            """
            It is the same outcome again: tracking has not moved for five days, \
            leaving delivery delayed.
            """
        )

        XCTAssertGreaterThanOrEqual(analysis.complaint.confidence, 0.60)
        XCTAssertFalse(analysis.task.isDetected)
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

    func testIntentModelsPreserveAutomaticRoutingApproval() async {
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
        XCTAssertTrue(isThresholdCrossing(invitation.invitation))
        XCTAssertEqual(
            invitation.invitation.isDetected,
            invitation.invitation.isApprovedForAutomaticRouting
        )
        XCTAssertTrue(isThresholdCrossing(complaint.complaint))
        XCTAssertEqual(
            complaint.complaint.isDetected,
            complaint.complaint.isApprovedForAutomaticRouting
        )
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

    func testPersonalPlanDoesNotBecomeAutomaticTask() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            "私人备忘：我准备周五自己整理完这份报告。"
        )

        XCTAssertTrue(analysis.task.isApprovedForAutomaticRouting)
        XCTAssertFalse(analysis.task.isDetected)
        XCTAssertFalse(analysis.replyableMessage.isDetected)
    }

    func testNewIntentModelsDetectEnglishAndChineseExamples() async {
        let analyzer = ClipboardSemanticAnalyzer()
        let samples: [
            (
                name: String,
                text: String,
                label: KeyPath<ClipboardSemanticAnalysis, ClipboardIntentLabel>
            )
        ] = [
            (
                "English schedule negotiation",
                "We need to reschedule the review. Is Tuesday or Thursday better?",
                \.scheduleNegotiation
            ),
            (
                "Chinese schedule negotiation",
                "周二下午还是周三下午开会更方便？",
                \.scheduleNegotiation
            ),
            (
                "English confirmation decision",
                "I approve the revised proposal; proceed with this version.",
                \.confirmationDecision
            ),
            (
                "Chinese confirmation decision",
                "我批准这版方案，就按这个版本继续推进。",
                \.confirmationDecision
            ),
            (
                "English follow-up reminder",
                "Reminder: create the release tag before 3 PM.",
                \.followUpReminder
            ),
            (
                "Chinese follow-up reminder",
                "提醒一下，下次会议前要创建发布标签。",
                \.followUpReminder
            ),
            (
                "English blessing",
                "Happy birthday! Wishing you a joyful year filled with good health.",
                \.blessing
            ),
            (
                "Chinese third-party blessing",
                "群里的朋友们，一起祝王老师生日快乐、身体健康！",
                \.blessing
            )
        ]

        for sample in samples {
            let analysis = await analyzer.analyze(sample.text)
            let label = analysis[keyPath: sample.label]
            XCTAssertTrue(
                isThresholdCrossing(label),
                "\(sample.name) confidence \(label.confidence) is below \(label.threshold)"
            )
            XCTAssertEqual(
                label.isDetected,
                label.isApprovedForAutomaticRouting,
                "\(sample.name) does not preserve routing approval"
            )
        }
    }

    func testNewIntentModelsRejectLexicallySimilarHardNegatives() async {
        let analyzer = ClipboardSemanticAnalyzer()
        let samples: [
            (
                name: String,
                text: String,
                label: KeyPath<ClipboardSemanticAnalysis, ClipboardIntentLabel>
            )
        ] = [
            (
                "English fixed schedule",
                "The meeting was confirmed for Tuesday and the calendar is already updated.",
                \.scheduleNegotiation
            ),
            (
                "Chinese fixed schedule",
                "会议已经确定在周二，日历也更新好了。",
                \.scheduleNegotiation
            ),
            (
                "English pending approval",
                "Message received; this does not mean approval.",
                \.confirmationDecision
            ),
            (
                "Chinese pending approval",
                "消息已阅，不代表审批通过。",
                \.confirmationDecision
            ),
            (
                "English uncertain follow-up",
                "Someone may follow up if there is time, but it is uncertain.",
                \.followUpReminder
            ),
            (
                "Chinese uncertain follow-up",
                "有空的话或许跟进，但不确定。",
                \.followUpReminder
            ),
            (
                "English quoted blessing",
                "The article quotes the phrase “wishing you good health.”",
                \.blessing
            ),
            (
                "Chinese occasion announcement",
                "今天是小林生日，蛋糕已经送到会议室。",
                \.blessing
            )
        ]

        for sample in samples {
            let analysis = await analyzer.analyze(sample.text)
            let label = analysis[keyPath: sample.label]
            XCTAssertFalse(
                isThresholdCrossing(label),
                "\(sample.name) false positive at confidence \(label.confidence)"
            )
            XCTAssertFalse(label.isDetected)
        }
    }

    func testNewIntentModelsSupportMultipleLabels() async {
        let analyzer = ClipboardSemanticAnalyzer()

        let scheduleQuestion = await analyzer.analyze(
            "We need to reschedule the review. Is Tuesday or Thursday better?"
        )

        XCTAssertTrue(isThresholdCrossing(scheduleQuestion.scheduleNegotiation))
        XCTAssertTrue(isThresholdCrossing(scheduleQuestion.question))
    }

    func testScheduleNegotiationCombinesWithDeterministicDateDetection() async {
        let analysis = await ClipboardSemanticAnalyzer().analyze(
            "Would September 2 or September 3, 2026 at 3 PM work for the review?"
        )

        XCTAssertTrue(isThresholdCrossing(analysis.scheduleNegotiation))
        XCTAssertTrue(analysis.hasDateOrTime)
        XCTAssertGreaterThanOrEqual(analysis.dates.count, 2)
    }

    func testTenModelColdAndWarmLatencyBudgets() async {
        let analyzer = ClipboardSemanticAnalyzer()
        let text = "Could we move Tuesday's review to Thursday, then remind me to follow up?"
        let clock = ContinuousClock()

        let coldStart = clock.now
        _ = await analyzer.analyze(text)
        let coldMilliseconds = milliseconds(from: coldStart.duration(to: clock.now))

        let iterations = 20
        let warmStart = clock.now
        for _ in 0..<iterations {
            _ = await analyzer.analyze(text)
        }
        let warmTotalMilliseconds = milliseconds(from: warmStart.duration(to: clock.now))
        let warmAverageMilliseconds = warmTotalMilliseconds / Double(iterations)

        print(
            "CLIPBOARD_SEMANTIC_BENCHMARK "
                + "coldMs=\(coldMilliseconds) "
                + "warmAverageMs=\(warmAverageMilliseconds)"
        )
        XCTAssertLessThan(coldMilliseconds, 2_000)
        XCTAssertLessThan(warmAverageMilliseconds, 200)
    }

    private func isThresholdCrossing(_ label: ClipboardIntentLabel) -> Bool {
        label.confidence > 0 && label.confidence >= label.threshold
    }

    private func milliseconds(from duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
