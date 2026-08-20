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
    func testVisibleDefaultsAreReplySummarizeTranslate() {
        XCTAssertEqual(
            AIClipboardSkillCatalog.visible().map(\.id),
            ["reply", "summarize", "translate"]
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

    func testTranslateFollowsUserTargetLanguage() {
        let ja = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.translateID,
            locale: "zh",
            translationTargetLocaleId: "ja"
        )
        XCTAssertTrue(ja.contains("Japanese"))
        XCTAssertFalse(ja.contains("互译"))
    }

    func testTranslateFallsBackToChineseEnglishWhenUnset() {
        let zh = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.translateID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(zh.contains("中文与英文"))
        let en = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.translateID,
            locale: "en",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(en.lowercased().contains("chinese"))
        XCTAssertTrue(en.lowercased().contains("english"))
    }

    func testTranslateButtonTitleUsesDirectionPairsAndTargetShortNames() {
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
                uiLanguage: .chinese
            ),
            "中↔英"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
                uiLanguage: .english
            ),
            "CN↔EN"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "en",
                uiLanguage: .chinese
            ),
            "中译英"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "de",
                uiLanguage: .chinese
            ),
            "中译德"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "ja",
                uiLanguage: .english
            ),
            "To JP"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "zh-Hans",
                uiLanguage: .english
            ),
            "To CN"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "zh-Hant",
                uiLanguage: .english
            ),
            "To TW"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "zh-Hans",
                uiLanguage: .chinese
            ),
            "简↔繁"
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.translateButtonTitle(
                translationTargetLocaleId: "zh-Hant",
                uiLanguage: .chinese
            ),
            "简↔繁"
        )
    }

    func testSummarizeAsksForOverviewNotShortening() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.summarizeID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
        )
        XCTAssertTrue(prompt.contains("概括"))
        XCTAssertTrue(prompt.contains("不要改写成可发送的短消息"))
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
