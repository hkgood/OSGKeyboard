// AIHintKeywordExtractorTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class AIHintKeywordExtractorTests: XCTestCase {
    func testTrendingPrefersMetadataTitleOverHotPrefix() throws {
        let json = """
        {"id":"hot-1","text":"全网热点：朱镕基同志逝世","prompt":"请概括","category":"society","source":"tophub-open-hot","locale":"zh","metadata":{"title":"朱镕基同志逝世"}}
        """
        let card = try JSONDecoder().decode(AIHintCard.self, from: Data(json.utf8))
        XCTAssertEqual(card.visualKind, .trending)
        XCTAssertEqual(card.visualKind.systemImage, "flame.fill")
        XCTAssertEqual(card.resolvedDisplayText, "朱镕基同志逝世")
    }

    func testWeatherUsesCityAndTemperature() {
        let card = AIHintCard(
            id: "weather-zh-上海",
            displayText: "上海天气速览",
            prompt: "请说明天气",
            category: "weather",
            source: "open-meteo",
            locale: "zh",
            metadata: AIHintMetadata(city: "上海", tempC: 25.6)
        )
        XCTAssertEqual(card.visualKind, .weather)
        XCTAssertEqual(card.resolvedDisplayText, "上海 26°")
    }

    func testHolidayStripsPrefixAndUsesChineseName() {
        let card = AIHintCard(
            id: "holiday-next-cn",
            displayText: "临近节日：中秋节",
            prompt: "介绍中秋",
            category: "holiday",
            source: "nager-holidays",
            locale: "zh",
            conditions: ["date"],
            metadata: AIHintMetadata(name: "Mid-Autumn Festival")
        )
        XCTAssertEqual(card.visualKind, .calendar)
        XCTAssertEqual(card.resolvedDisplayText, "中秋节")
    }

    func testEnglishHolidayUsesMetadataName() {
        let card = AIHintCard(
            id: "holiday-next-us",
            displayText: "Upcoming: Labour Day",
            prompt: "Explain Labour Day",
            category: "holiday",
            source: "nager-holidays",
            locale: "en",
            metadata: AIHintMetadata(name: "Labour Day")
        )
        XCTAssertEqual(card.resolvedDisplayText, "Labour Day")
    }

    func testLongOrgTitleFallsBackToLastChunk() {
        let text = "中共中央 全国人大常委会 国务院 全国政协讣告 朱镕基同志逝世"
        XCTAssertEqual(
            AIHintKeywordExtractor.finalize(text, locale: "zh"),
            "朱镕基同志逝世"
        )
    }

    func testMixedTitlePrefersLeadingLatin() {
        XCTAssertEqual(
            AIHintKeywordExtractor.finalize(
                "DeepSeek Pro 正式版已经发布，如何评价该模型？",
                locale: "zh"
            ),
            "DeepSeek"
        )
    }

    func testDailyBriefIsNewsAndSoulQuoteIsSearch() {
        let brief = AIHintCard(
            id: "tophub-daily-brief-1",
            displayText: "看看今日早报",
            prompt: "写早报",
            category: "daily",
            source: "tophub-daily",
            locale: "zh"
        )
        XCTAssertEqual(brief.visualKind, .news)
        XCTAssertEqual(brief.resolvedDisplayText, "今日早报")

        let soul = AIHintCard(
            id: "tophub-daily-soul-1",
            displayText: "今日一句：展开聊聊",
            prompt: "解释这句话",
            category: "daily",
            source: "tophub-daily",
            locale: "zh",
            metadata: AIHintMetadata(soul: "为了防止我这个月又乱花钱")
        )
        XCTAssertEqual(soul.visualKind, .search)
        XCTAssertEqual(soul.resolvedDisplayText, "今日金句")
    }

    func testCapabilityMapsToSearch() {
        let card = AIHintLocalCatalog.cards(locale: "zh")
            .first { $0.id == "local-zh-encyclopedia" }!
        XCTAssertEqual(card.visualKind, .search)
        XCTAssertEqual(card.resolvedDisplayText, "有趣概念")
    }

    func testStocksMapsToChartIcon() {
        let card = AIHintLocalCatalog.cards(locale: "zh")
            .first { $0.id == "local-zh-stocks" }!
        XCTAssertEqual(card.visualKind, .stocks)
        XCTAssertEqual(card.resolvedDisplayText, "今日大盘")
    }
}

final class AIClipboardSkillTests: XCTestCase {
    func testVisibleDefaultsContainEveryBuiltInSkill() {
        XCTAssertEqual(
            AIClipboardSkillCatalog.visible().map(\.id),
            AIClipboardSkillCatalog.catalog.map(\.id)
        )
    }

    func testVisibleRespectsEnabledIDsForFutureSettings() {
        XCTAssertEqual(
            AIClipboardSkillCatalog.visible(enabledIDs: ["translate", "reply"]).map(\.id),
            ["translate", "reply"]
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.visible(enabledIDs: ["unknown"]).map(\.id),
            []
        )
    }

    func testTranslateUsesPrimarySystemLanguage() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.translateID,
            locale: "zh",
            translationTargetLocaleId: "ja",
            preferredLanguages: ["de-DE"]
        )
        XCTAssertTrue(prompt.contains("German"))
        XCTAssertFalse(prompt.contains("Japanese"))
        XCTAssertTrue(prompt.contains("原样输出"))
    }

    func testTranslateUsesSystemLanguageWhenPostTranslationIsOff() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.translateID,
            locale: "en",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            preferredLanguages: ["ja-JP"]
        )
        XCTAssertTrue(prompt.contains("Japanese"))
        XCTAssertTrue(prompt.contains("system language"))
    }

    func testTranslateButtonTitleUsesSystemLanguage() {
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "de",
                uiLanguage: .chinese,
                preferredLanguages: ["en-US"]
            ),
            "译为英语"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
                uiLanguage: .english,
                preferredLanguages: ["ja-JP"]
            ),
            "To Japanese"
        )
    }

    func testSummarizeAsksForOverviewNotShortening() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.summarizeID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("总结"))
        XCTAssertTrue(prompt.contains("决定、结论和下一步"))
    }

    func testSemanticReplySkillsHaveDistinctInstructions() {
        let ids = [
            AIClipboardSkillCatalog.playfulReplyID,
            AIClipboardSkillCatalog.acceptInvitationID,
            AIClipboardSkillCatalog.declineInvitationID,
            AIClipboardSkillCatalog.acceptTaskID,
            AIClipboardSkillCatalog.clarifyRequestID,
            AIClipboardSkillCatalog.empathyReplyID,
            AIClipboardSkillCatalog.businessReplyID,
            AIClipboardSkillCatalog.summarizeID,
            AIClipboardSkillCatalog.organizeListID
        ]
        let prompts = ids.map {
            AIClipboardSkillCatalog.instruction(
                skillID: $0,
                locale: "zh",
                translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
            )
        }
        XCTAssertEqual(Set(prompts).count, ids.count)
        XCTAssertFalse(prompts.contains { $0.contains("用户选择的操作") })
    }

    func testPlayfulReplyIsWittyButKeepsSafetyBoundaries() throws {
        let skill = try XCTUnwrap(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.playfulReplyID)
        )
        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )

        XCTAssertTrue(skill.supportsReplyStyle)
        XCTAssertTrue(instruction.contains("脱口秀演员"))
        XCTAssertTrue(instruction.contains("不攻击对方"))
        XCTAssertTrue(instruction.contains("严肃或敏感内容时收住幽默"))
        XCTAssertTrue(instruction.contains("普通人在和朋友、好友或同事聊天"))
    }

    func testReplyUsesConversationalBaselineAndOptionalLearnedStyle() throws {
        let skill = try XCTUnwrap(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.replyID)
        )
        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            replyStyle: AIClipboardReplyStyleContext(
                styleID: "user.learned",
                prompt: "喜欢短句，常用“行”“可以”，不说客套话。"
            )
        )

        XCTAssertTrue(instruction.contains("普通人在和朋友、好友或同事聊天"))
        XCTAssertTrue(instruction.contains("1 个合适的表情或 Emoji"))
        XCTAssertTrue(instruction.contains("<user_reply_style"))
        XCTAssertTrue(instruction.contains("喜欢短句"))
        XCTAssertTrue(instruction.contains("不能改变当前技能的意图"))
    }

    func testReplyStyleIsNotInjectedIntoNonReplySkill() throws {
        let skill = try XCTUnwrap(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.summarizeID)
        )
        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            replyStyle: AIClipboardReplyStyleContext(
                styleID: "user.learned",
                prompt: "这是个人回复风格"
            )
        )

        XCTAssertFalse(instruction.contains("user_reply_style"))
        XCTAssertFalse(instruction.contains("这是个人回复风格"))
    }

    func testReplyStyleResolverAcceptsOnlyUserOwnedStyle() {
        let user = PolishStylePack(
            id: "user.learned",
            name: "我的风格",
            prompt: "喜欢短句",
            kind: .user
        )
        let builtIn = PolishStylePack(
            id: "builtin.formal",
            name: "正式",
            prompt: "使用正式表达",
            kind: .builtin
        )

        XCTAssertEqual(
            AIClipboardReplyStyleContext.resolve(activeStyle: user)?.prompt,
            "喜欢短句"
        )
        XCTAssertNil(AIClipboardReplyStyleContext.resolve(activeStyle: builtIn))
    }

    func testBusinessReplyKeepsProfessionalBaselineWithoutFriendEmojiGuidance() throws {
        let skill = try XCTUnwrap(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.businessReplyID)
        )
        let instruction = AIClipboardSkillCatalog.instruction(
            for: skill,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )

        XCTAssertTrue(instruction.contains("同事之间正常沟通"))
        XCTAssertFalse(instruction.contains("朋友、好友"))
        XCTAssertFalse(instruction.contains("表情或 Emoji"))
    }

    func testExtractTodosAsksForNONEWhenEmpty() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.extractTodosID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("NONE"))
        XCTAssertTrue(prompt.contains("不要把整段原文当成一条待办"))
    }

    func testExtractEventsAsksForNONEWhenEmpty() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.extractEventsID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("NONE"))
        XCTAssertTrue(prompt.contains("开始|结束|标题|地点"))
    }

    func testNavigateAsksForNONEWhenEmpty() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.navigateID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("NONE"))
        XCTAssertTrue(prompt.contains("起点|终点"))
    }

    func testSaveToNotesAsksForTitleNotBody() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.saveToNotesID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("标题"))
        XCTAssertTrue(prompt.contains("不要输出正文"))
        XCTAssertTrue(prompt.contains("不要输出 NONE"))
    }
}
