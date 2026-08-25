// ClipboardSkillSemanticRankerTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class ClipboardSkillSemanticRankerTests: XCTestCase {
    func testForeignQuestionPromotesSystemTranslationAndSourceLanguageReply() {
        let ranked = rank(
            text: "Could you send me the final proposal by Friday?",
            analysis: analysis(language: "en", question: detected())
        )

        XCTAssertEqual(
            Array(ranked.prefix(3)),
            [
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.clarifyRequestID
            ]
        )
    }

    func testTranslationIsNotRecommendedForSystemLanguage() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "Could you send me the final proposal?",
            analysis: analysis(language: "en", question: detected()),
            uiLanguage: .chinese,
            limit: 5,
            preferredLanguages: ["en-US"]
        ).map(\.id)

        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.translateID))
        XCTAssertTrue(recommendations.contains(AIClipboardSkillCatalog.replyID))
    }

    func testChineseScriptMismatchPromotesTranslation() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "這是一段繁體中文。",
            analysis: analysis(language: "zh-Hant"),
            uiLanguage: .chinese,
            limit: 5,
            preferredLanguages: ["zh-Hans"]
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.translateID,
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

    func testSingleHTTPSLinkOffersOpenAndWebpageSummary() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "https://example.com/article",
            analysis: analysis(urls: [URL(string: "https://example.com/article")!]),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.openLinkID,
                AIClipboardSkillCatalog.summarizeWebPageID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testRealStandaloneURLAnalysisOnlyOffersLinkSkills() async {
        let text = "https://www.apple.com/newsroom/"
        let detected = await ClipboardSemanticAnalyzer().analyze(text)
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: text,
            analysis: detected,
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.openLinkID,
                AIClipboardSkillCatalog.summarizeWebPageID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testMultipleLinksDoNotChooseAnAmbiguousTarget() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "https://example.com/a https://example.com/b",
            analysis: analysis(urls: [
                URL(string: "https://example.com/a")!,
                URL(string: "https://example.com/b")!
            ]),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.openLinkID))
        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.summarizeWebPageID))
        XCTAssertEqual(recommendations, [AIClipboardSkillCatalog.replyID])
    }

    func testSinglePhoneNumberOffersCallAndCreateContact() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "请拨打 +1 408-996-1010",
            analysis: analysis(
                phoneNumbers: [
                    ClipboardTextLabel(sourceText: "+1 408-996-1010")
                ]
            ),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.callPhoneID,
                AIClipboardSkillCatalog.createContactID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testRealPhoneAnalysisOnlyOffersPhoneActions() async {
        let text = "联系电话：+1 408-996-1010"
        let detected = await ClipboardSemanticAnalyzer().analyze(text)
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: text,
            analysis: detected,
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.callPhoneID,
                AIClipboardSkillCatalog.createContactID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testMultiplePhoneNumbersDoNotChooseAnAmbiguousTarget() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "+1 408-996-1010 / 400-666-8800",
            analysis: analysis(
                phoneNumbers: [
                    ClipboardTextLabel(sourceText: "+1 408-996-1010"),
                    ClipboardTextLabel(sourceText: "400-666-8800")
                ]
            ),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.callPhoneID))
        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.createContactID))
        XCTAssertEqual(recommendations, [AIClipboardSkillCatalog.replyID])
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
        XCTAssertEqual(ranked.dropFirst().first, AIClipboardSkillCatalog.clarifyRequestID)
    }

    func testLongTextPromotesIntegratedSummaryAndNotes() {
        let ranked = rank(
            text: String(repeating: "这是需要阅读和整理的长文内容。", count: 40),
            analysis: analysis()
        )

        XCTAssertEqual(
            Array(ranked.prefix(2)),
            [
                AIClipboardSkillCatalog.summarizeID,
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

    func testRecommendationsAddReplyToSemanticallyRelevantSkills() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "北京市朝阳区望京街 10 号，到了给我电话。",
            analysis: analysis(hasAddress: true),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.navigateID,
                AIClipboardSkillCatalog.replyID
            ]
        )
        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.summarizeID))
        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.translateID))
    }

    func testRecommendationsFallBackToReplyWhenNoSemanticLabelMatches() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "知道了",
            analysis: analysis(),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(recommendations, [AIClipboardSkillCatalog.replyID])
    }

    func testNegativeReplyableMessageDoesNotOfferPlayfulReply() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "我刚到家，今天真是累坏了。",
            analysis: analysis(
                sentiment: .negative,
                replyableMessage: detected()
            ),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(recommendations, [AIClipboardSkillCatalog.replyID])
    }

    func testInvitationKeepsSpecificRepliesAndGenericReply() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "今晚七点老地方吃饭，你能来吗？",
            analysis: analysis(
                hasDate: true,
                question: detected(),
                invitation: detected(),
                replyableMessage: detected()
            ),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.extractEventsID,
                AIClipboardSkillCatalog.acceptInvitationID,
                AIClipboardSkillCatalog.declineInvitationID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testForeignQuestionKeepsReplyAndOneSpecializedFollowUp() {
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "Could you send the final proposal by Friday?",
            analysis: analysis(
                language: "en",
                question: detected(),
                replyableMessage: detected()
            ),
            uiLanguage: .chinese,
            limit: 5,
            preferredLanguages: ["zh-Hans"]
        )
        let replyCount = recommendations.filter(\.supportsReplyStyle).count

        XCTAssertLessThanOrEqual(replyCount, 2)
        XCTAssertEqual(
            recommendations.map(\.id),
            [
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.clarifyRequestID
            ]
        )
    }

    private func rank(
        text: String,
        analysis: ClipboardSemanticAnalysis
    ) -> [String] {
        ClipboardSkillSemanticRanker.ranked(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: text,
            analysis: analysis,
            uiLanguage: .chinese,
            preferredLanguages: ["zh-Hans"]
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
        urls: [URL] = [],
        phoneNumbers: [ClipboardTextLabel] = [],
        sentiment: ClipboardSentimentLabel = .unknown,
        task: ClipboardIntentLabel? = nil,
        question: ClipboardIntentLabel? = nil,
        invitation: ClipboardIntentLabel? = nil,
        complaint: ClipboardIntentLabel? = nil,
        replyableMessage: ClipboardIntentLabel? = nil
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
            phoneNumbers: phoneNumbers,
            urls: urls,
            personNames: [],
            organizationNames: [],
            sentiment: sentiment,
            sentimentConfidence: sentiment == .unknown ? 0 : 0.9,
            task: task ?? absent(),
            question: question ?? absent(),
            invitation: invitation ?? absent(),
            complaint: complaint ?? absent(),
            replyableMessage: replyableMessage ?? absent()
        )
    }
}
