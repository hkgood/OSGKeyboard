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

    func testUnapprovedComplaintFallsBackToGenericReply() {
        let complaint = ClipboardIntentLabel(
            confidence: 0.82,
            threshold: 0.6,
            isDetected: false,
            isApprovedForAutomaticRouting: false
        )
        let recommendations = ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: "这个问题已经发生三次了，请尽快处理。",
            analysis: analysis(
                sentiment: .negative,
                complaint: complaint
            ),
            uiLanguage: .chinese,
            limit: 5
        ).map(\.id)

        XCTAssertEqual(recommendations, [AIClipboardSkillCatalog.replyID])
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

    func testScheduleNegotiationMapsToExistingSkills() {
        let recommendations = recommended(
            text: "Would Tuesday or Wednesday work better for our meeting?",
            analysis: analysis(scheduleNegotiation: detected())
        )

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.clarifyRequestID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.extractEventsID
            ]
        )
    }

    func testScheduleNegotiationWithDatesPromotesEventExtraction() {
        let recommendations = recommended(
            text: "周二下午还是周三下午开会更方便？",
            analysis: analysis(
                hasDate: true,
                scheduleNegotiation: detected()
            )
        )

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.extractEventsID,
                AIClipboardSkillCatalog.clarifyRequestID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testConfirmationDecisionMapsToExistingSkills() {
        let recommendations = recommended(
            text: "Please confirm whether we should proceed or pause.",
            analysis: analysis(confirmationDecision: detected())
        )

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.acceptTaskID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testFollowUpReminderMapsToExistingSkills() {
        let recommendations = recommended(
            text: "提醒一下，请在周五前跟进客户并同步进展。",
            analysis: analysis(followUpReminder: detected())
        )

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.extractTodosID,
                AIClipboardSkillCatalog.acceptTaskID,
                AIClipboardSkillCatalog.clarifyRequestID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testBlessingMapsToDedicatedReplyAndGenericFallback() {
        let recommendations = recommended(
            text: "大家一起祝王老师生日快乐、身体健康！",
            analysis: analysis(
                replyableMessage: detected(),
                blessing: detected()
            )
        )

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.blessingReplyID,
                AIClipboardSkillCatalog.replyID
            ]
        )
    }

    func testNewIntentConflictKeepsTopFiveAndGenericReply() {
        let recommendations = recommended(
            text: "请确认周二还是周三开会，并提醒我之后跟进客户。",
            analysis: analysis(
                hasDate: true,
                replyableMessage: detected(),
                scheduleNegotiation: detected(),
                confirmationDecision: detected(),
                followUpReminder: detected()
            )
        )

        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.acceptTaskID,
                AIClipboardSkillCatalog.clarifyRequestID,
                AIClipboardSkillCatalog.extractEventsID,
                AIClipboardSkillCatalog.extractTodosID
            ]
        )
        XCTAssertEqual(recommendations.count, 5)
    }

    func testSpecializedNewIntentSuppressesGenericReplyableBoost() {
        let recommendations = recommended(
            text: "Would Tuesday or Wednesday work better?",
            analysis: analysis(
                replyableMessage: detected(),
                scheduleNegotiation: detected()
            )
        )

        XCTAssertFalse(recommendations.contains(AIClipboardSkillCatalog.playfulReplyID))
        XCTAssertEqual(
            recommendations,
            [
                AIClipboardSkillCatalog.clarifyRequestID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.extractEventsID
            ]
        )
    }

    func testAnalyzerToRecommendationsForNewIntents() async {
        let analyzer = ClipboardSemanticAnalyzer()
        let samples: [
            (
                text: String,
                label: KeyPath<ClipboardSemanticAnalysis, ClipboardIntentLabel>,
                expectedSkillIDs: [String]
            )
        ] = [
            (
                "We need to reschedule the review. Is Tuesday or Thursday better?",
                \.scheduleNegotiation,
                [
                    AIClipboardSkillCatalog.clarifyRequestID,
                    AIClipboardSkillCatalog.replyID,
                    AIClipboardSkillCatalog.extractEventsID
                ]
            ),
            (
                "I approve the revised proposal; proceed with this version.",
                \.confirmationDecision,
                [
                    AIClipboardSkillCatalog.acceptTaskID,
                    AIClipboardSkillCatalog.replyID
                ]
            ),
            (
                "提醒一下，下次会议前要创建发布标签。",
                \.followUpReminder,
                [
                    AIClipboardSkillCatalog.extractTodosID,
                    AIClipboardSkillCatalog.acceptTaskID,
                    AIClipboardSkillCatalog.clarifyRequestID,
                    AIClipboardSkillCatalog.replyID
                ]
            )
        ]

        for sample in samples {
            let detected = await analyzer.analyze(sample.text)
            let label = detected[keyPath: sample.label]
            let recommendations = recommended(text: sample.text, analysis: detected)

            XCTAssertTrue(
                isThresholdCrossing(label),
                "confidence \(label.confidence) is below \(label.threshold) for \(sample.text)"
            )
            for expectedID in sample.expectedSkillIDs {
                XCTAssertTrue(
                    recommendations.contains(expectedID),
                    "\(expectedID) missing for \(sample.text)"
                )
            }
        }
    }

    @MainActor
    func testRankingStorePublishesAnalysisForMatchingEntry() async {
        let probe = ClipboardSemanticAnalyzerProbe()
        let expectedAnalysis = analysis(followUpReminder: detected())
        let store = ClipboardSemanticRankingStore { text in
            await probe.analyze(text)
        }
        let entry = ClipboardHistoryEntry(text: "follow up")

        store.analyze(entry)
        await waitUntil { await probe.hasRequest(for: entry.text) }
        await probe.resolve(entry.text, with: expectedAnalysis)
        await waitUntil { store.snapshot != nil }

        XCTAssertEqual(store.snapshot?.entryID, entry.id)
        XCTAssertEqual(store.snapshot?.analysis, expectedAnalysis)
    }

    @MainActor
    func testRankingStoreRapidAnalyzeIgnoresCancelledResult() async {
        let probe = ClipboardSemanticAnalyzerProbe()
        let firstAnalysis = analysis(scheduleNegotiation: detected())
        let secondAnalysis = analysis(confirmationDecision: detected())
        let store = ClipboardSemanticRankingStore { text in
            await probe.analyze(text)
        }
        let first = ClipboardHistoryEntry(text: "first")
        let second = ClipboardHistoryEntry(text: "second")

        store.analyze(first)
        await waitUntil { await probe.hasRequest(for: first.text) }
        store.analyze(second)
        XCTAssertNil(store.snapshot)
        await waitUntil { await probe.hasRequest(for: second.text) }

        await probe.resolve(second.text, with: secondAnalysis)
        await waitUntil { store.snapshot?.entryID == second.id }
        await probe.resolve(first.text, with: firstAnalysis)
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(store.snapshot?.entryID, second.id)
        XCTAssertEqual(store.snapshot?.analysis, secondAnalysis)
    }

    @MainActor
    func testRankingStoreClearInvalidatesPendingAnalysis() async {
        let probe = ClipboardSemanticAnalyzerProbe()
        let store = ClipboardSemanticRankingStore { text in
            await probe.analyze(text)
        }
        let entry = ClipboardHistoryEntry(text: "pending")

        store.analyze(entry)
        await waitUntil { await probe.hasRequest(for: entry.text) }
        store.clear()
        XCTAssertNil(store.snapshot)

        await probe.resolve(entry.text, with: analysis())
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertNil(store.snapshot)
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

    private func recommended(
        text: String,
        analysis: ClipboardSemanticAnalysis
    ) -> [String] {
        ClipboardSkillSemanticRanker.recommended(
            skills: AIClipboardSkillCatalog.catalog,
            sourceText: text,
            analysis: analysis,
            uiLanguage: .chinese,
            limit: 5,
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

    private func isThresholdCrossing(_ label: ClipboardIntentLabel) -> Bool {
        label.confidence > 0 && label.confidence >= label.threshold
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
        replyableMessage: ClipboardIntentLabel? = nil,
        scheduleNegotiation: ClipboardIntentLabel? = nil,
        confirmationDecision: ClipboardIntentLabel? = nil,
        followUpReminder: ClipboardIntentLabel? = nil,
        blessing: ClipboardIntentLabel? = nil
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
            replyableMessage: replyableMessage ?? absent(),
            scheduleNegotiation: scheduleNegotiation ?? absent(),
            confirmationDecision: confirmationDecision ?? absent(),
            followUpReminder: followUpReminder ?? absent(),
            blessing: blessing ?? absent(),
            actionVerifier: nil,
            coordinationVerifier: nil
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping () async -> Bool
    ) async {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Condition was not met before timeout.")
    }
}

private actor ClipboardSemanticAnalyzerProbe {
    private var requestedTexts = Set<String>()
    private var continuations: [
        String: CheckedContinuation<ClipboardSemanticAnalysis, Never>
    ] = [:]

    func analyze(_ text: String) async -> ClipboardSemanticAnalysis {
        requestedTexts.insert(text)
        return await withCheckedContinuation { continuation in
            continuations[text] = continuation
        }
    }

    func hasRequest(for text: String) -> Bool {
        requestedTexts.contains(text)
    }

    func resolve(
        _ text: String,
        with analysis: ClipboardSemanticAnalysis
    ) {
        continuations.removeValue(forKey: text)?.resume(returning: analysis)
    }
}
