// AIEventExtractionTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class AIEventExtractionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var now: Date {
        date(2026, 8, 13, 20, 24)
    }

    func testNONEAndEmptyProduceNoItems() {
        XCTAssertEqual(lines("NONE"), [])
        XCTAssertEqual(lines("没有日期或时间"), [])
        XCTAssertEqual(lines("no events"), [])
        XCTAssertEqual(lines("  \n  "), [])
    }

    func testAllDayDateOnly() {
        XCTAssertEqual(
            lines("2026-08-15||提交周报|"),
            ["2026-08-15|ALLDAY|提交周报|"]
        )
    }

    func testTimedFillsDefaultOneHour() {
        XCTAssertEqual(
            lines("2026-08-15 14:00||项目评审|"),
            ["2026-08-15 14:00|2026-08-15 15:00|项目评审|"]
        )
    }

    func testTimedKeepsExplicitEndAndLocation() {
        XCTAssertEqual(
            lines("2026-08-15 14:00|2026-08-15 16:00|项目评审|3楼会议室"),
            ["2026-08-15 14:00|2026-08-15 16:00|项目评审|3楼会议室"]
        )
    }

    func testTimeOnlyUsesToday() {
        XCTAssertEqual(
            lines("15:00||打电话给客户|"),
            ["2026-08-13 15:00|2026-08-13 16:00|打电话给客户|"]
        )
    }

    func testTimeOnlyEndOnSameDayOvernightRollsForward() {
        XCTAssertEqual(
            lines("2026-08-15 23:00|01:00|跨夜值班|"),
            ["2026-08-15 23:00|2026-08-16 01:00|跨夜值班|"]
        )
    }

    func testTwoFieldStartAndTitle() {
        XCTAssertEqual(
            lines("2026-08-15 14:00|开会"),
            ["2026-08-15 14:00|2026-08-15 15:00|开会|"]
        )
    }

    func testThreeFieldStartTitleLocationWhenMiddleIsNotATime() {
        XCTAssertEqual(
            lines("2026-08-15 14:00|开会|会议室A"),
            ["2026-08-15 14:00|2026-08-15 15:00|开会|会议室A"]
        )
    }

    func testDropsLinesWithoutStartOrTitle() {
        let raw = """
        买牛奶
        ||无开始|
        2026-08-15 14:00||
        2026-08-16||有效全天|
        """
        XCTAssertEqual(lines(raw), ["2026-08-16|ALLDAY|有效全天|"])
    }

    func testMultipleEventsCapAtTwenty() {
        let raw = (1...25).map { "2026-08-15 10:00||任务\($0)|" }.joined(separator: "\n")
        let items = lines(raw)
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.first, "2026-08-15 10:00|2026-08-15 11:00|任务1|")
        XCTAssertEqual(items.last, "2026-08-15 10:00|2026-08-15 11:00|任务20|")
    }

    func testWholeClipboardEchoIsRejected() {
        let source = String(repeating: "这是一段很长的会议纪要内容，包含许多句子。", count: 4)
        XCTAssertEqual(
            AIEventExtraction.lines(
                from: "2026-08-15||\(source)|",
                sourceClipboard: source,
                now: now,
                calendar: calendar
            ),
            []
        )
    }

    func testPromptIncludesClockPipeContractAndNONE() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.extractEventsID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            now: now
        )
        XCTAssertTrue(prompt.contains("本地时区"))
        XCTAssertTrue(prompt.contains("开始|结束|标题|地点"))
        XCTAssertTrue(prompt.contains("NONE"))
        XCTAssertTrue(prompt.contains("不要把整段原文当成一条日程"))
    }

    func testEnglishPromptIncludesClockAndNONE() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.extractEventsID,
            locale: "en",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            now: now
        )
        XCTAssertTrue(prompt.contains("local timezone"))
        XCTAssertTrue(prompt.contains("NONE"))
        XCTAssertTrue(prompt.contains("all-day"))
    }

    private func lines(_ raw: String) -> [String] {
        AIEventExtraction.lines(from: raw, now: now, calendar: calendar)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = h
        components.minute = min
        return calendar.date(from: components)!
    }
}
