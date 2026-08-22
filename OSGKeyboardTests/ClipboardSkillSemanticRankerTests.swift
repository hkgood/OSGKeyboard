// ClipboardSkillSemanticRankerTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class ClipboardSkillSemanticRankerTests: XCTestCase {
    func testForeignQuestionPromotesTranslationAndSourceLanguageReply() {
        let ranked = rank(
            text: "Could you send me the final proposal by Friday?",
            analysis: analysis(language: "en", question: detected())
        )

        XCTAssertEqual(
            Array(ranked.prefix(3)),
            [
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.replyInSourceLanguageID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testInvitationWithDatePromotesCalendarAndBothReplyChoices() {
        let ranked = rank(
            text: "今晚七点老地方吃饭，你能来吗？",
            analysis: analysis(
                hasDate: true,
                question: detected(),
                invitation: detected()
            )
        )

        XCTAssertEqual(ranked.first, AIClipboardSkillCatalog.extractEventsID)
        XCTAssertLessThan(
            tryIndex(AIClipboardSkillCatalog.acceptInvitationID, in: ranked),
            tryIndex(AIClipboardSkillCatalog.summarizeID, in: ranked)
        )
        XCTAssertLessThan(
            tryIndex(AIClipboardSkillCatalog.declineInvitationID, in: ranked),
            tryIndex(AIClipboardSkillCatalog.summarizeID, in: ranked)
        )
    }

    func testAddressPromotesNavigation() {
        let ranked = rank(
            text: "北京市朝阳区望京街 10 号，到了给我电话。",
            analysis: analysis(hasAddress: true)
        )

        XCTAssertEqual(ranked.first, AIClipboardSkillCatalog.navigateID)
    }

    func testTaskListPromotesTodoAndOrganizationSkills() {
        let ranked = rank(
            text: "- 更新报价单\n- 给客户回邮件\n- 周五前提交合同",
            analysis: analysis(task: detected())
        )

        XCTAssertEqual(ranked.first, AIClipboardSkillCatalog.extractTodosID)
        XCTAssertLessThan(
            tryIndex(AIClipboardSkillCatalog.organizeListID, in: ranked),
            tryIndex(AIClipboardSkillCatalog.replyID, in: ranked)
        )
        XCTAssertLessThan(
            tryIndex(AIClipboardSkillCatalog.acceptTaskID, in: ranked),
            tryIndex(AIClipboardSkillCatalog.replyID, in: ranked)
        )
    }

    func testAdvisoryComplaintPromotesEmpathyWithoutAutomaticApproval() {
        let complaint = ClipboardIntentLabel(
            confidence: 0.82,
            threshold: 0.6,
            isDetected: false,
            isApprovedForAutomaticRouting: false
        )
        let ranked = rank(
            text: "这个问题已经发生三次了，请尽快处理。",
            analysis: analysis(
                sentiment: .negative,
                complaint: complaint
            )
        )

        XCTAssertEqual(ranked.first, AIClipboardSkillCatalog.empathyReplyID)
        XCTAssertEqual(ranked.dropFirst().first, AIClipboardSkillCatalog.askForDetailsID)
    }

    func testLongTextPromotesSummaryConclusionsAndNotes() {
        let ranked = rank(
            text: String(repeating: "这是需要阅读和整理的长文内容。", count: 40),
            analysis: analysis()
        )

        XCTAssertEqual(
            Array(ranked.prefix(3)),
            [
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.extractConclusionsID,
                AIClipboardSkillCatalog.saveToNotesID
            ]
        )
    }

    func testNoSignalPreservesSavedOrder() {
        let baseline = [
            AIClipboardSkillCatalog.businessReplyID,
            AIClipboardSkillCatalog.translateID,
            AIClipboardSkillCatalog.replyID
        ]
        let ranked = ClipboardSkillSemanticRanker.ranked(
            skills: skills(ids: baseline),
            sourceText: "好的",
            analysis: analysis(),
            uiLanguage: .chinese
        ).map(\.id)

        XCTAssertEqual(ranked, baseline)
    }

    func testRecommendationsSelectOnlySemanticallyRelevantSkills() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "北京市朝阳区望京街 10 号，到了给我电话。",
            analysis: analysis(hasAddress: true),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(recommendations, [AIClipboardSkillCatalog.navigateID])
        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.summarizeID))
        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.translateID))
    }

    func testRecommendationsStayEmptyWhenNoSemanticLabelMatches() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "知道了",
            analysis: analysis(),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertTrue(recommendations.isEmpty)
    }

    private func rank(
        text: String,
        analysis: ClipboardSemanticAnalysis
    ) -> [String] {
        ClipboardSkillSemanticRanker.ranked(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: text,
            analysis: analysis,
            uiLanguage: .chinese
        ).map(\.id)
    }

    private func skills(ids: [String]) -> [AIClipboardSkill] {
        ids.compactMap { AIClipboardSkillCatalog.skill(id: $0) }
    }

    private func tryIndex(_ id: String, in ids: [String]) -> Int {
        ids.firstIndex(of: id) ?? Int.max
    }

    private func detected() -> ClipboardIntentLabel {
        ClipboardIntentLabel(
            confidence: 0.95,
            threshold: 0.6,
            isDetected: true,
            isApprovedForAutomaticRouting: true
        )
    }

    private func absent() -> ClipboardIntentLabel {
        ClipboardIntentLabel(
            confidence: 0,
            threshold: 1,
            isDetected: false,
            isApprovedForAutomaticRouting: false
        )
    }

    private func analysis(
        language: String? = nil,
        hasDate: Bool = false,
        hasAddress: Bool = false,
        sentiment: ClipboardSentimentLabel = .unknown,
        task: ClipboardIntentLabel? = nil,
        question: ClipboardIntentLabel? = nil,
        invitation: ClipboardIntentLabel? = nil,
        complaint: ClipboardIntentLabel? = nil
    ) -> ClipboardSemanticAnalysis {
        ClipboardSemanticAnalysis(
            language: language.map {
                ClipboardLanguageLabel(identifier: $0, confidence: 0.99)
            },
            dates: hasDate
                ? [ClipboardDateLabel(
                    sourceText: "今晚七点",
                    date: Date(),
                    duration: 0,
                    timeZoneIdentifier: nil
                )]
                : [],
            addresses: hasAddress
                ? [ClipboardTextLabel(sourceText: "望京街 10 号")]
                : [],
            phoneNumbers: [],
            urls: [],
            personNames: [],
            organizationNames: [],
            sentiment: sentiment,
            sentimentConfidence: sentiment == .unknown ? 0 : 0.9,
            task: task ?? absent(),
            question: question ?? absent(),
            invitation: invitation ?? absent(),
            complaint: complaint ?? absent()
        )
    }
}
