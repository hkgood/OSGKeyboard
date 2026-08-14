// AINoteExportTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class AINoteExportTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private var now: Date {
        date(2026, 8, 13, 23, 56)
    }

    func testEmptyClipboardProducesNoItems() {
        XCTAssertEqual(items(from: "周会纪要", clipboard: nil), [])
        XCTAssertEqual(items(from: "周会纪要", clipboard: "  \n  "), [])
    }

    func testUsesModelTitleAndKeepsOriginalBody() {
        XCTAssertEqual(
            items(from: "8月13日周会纪要", clipboard: "第一项\n第二项"),
            ["8月13日周会纪要\(AINoteExport.fieldSeparator)第一项\n第二项"]
        )
    }

    func testIgnoresModelBodyAfterFirstLine() {
        let answer = """
        购物清单
        这是模型改写过的正文，不应写入备忘录。
        """
        XCTAssertEqual(
            items(from: answer, clipboard: "买牛奶\n买鸡蛋"),
            ["购物清单\(AINoteExport.fieldSeparator)买牛奶\n买鸡蛋"]
        )
    }

    func testTakesTitleBeforePipe() {
        XCTAssertEqual(
            items(from: "会议纪要|请忽略这段模型正文", clipboard: "原文"),
            ["会议纪要\(AINoteExport.fieldSeparator)原文"]
        )
    }

    func testNONEFallsBackToDatedSnippet() {
        XCTAssertEqual(
            items(from: "NONE", clipboard: "买牛奶"),
            ["8月13日 · 买牛奶\(AINoteExport.fieldSeparator)买牛奶"]
        )
        XCTAssertEqual(
            items(from: "没有标题", clipboard: "买牛奶"),
            ["8月13日 · 买牛奶\(AINoteExport.fieldSeparator)买牛奶"]
        )
    }

    func testEnglishFallbackUsesMonthDay() {
        XCTAssertEqual(
            items(from: "NONE", clipboard: "Buy milk", locale: "en"),
            ["13 Aug · Buy milk\(AINoteExport.fieldSeparator)Buy milk"]
        )
    }

    func testStripsQuotesAndBullets() {
        XCTAssertEqual(
            items(from: "「周会纪要」", clipboard: "纪要正文"),
            ["周会纪要\(AINoteExport.fieldSeparator)纪要正文"]
        )
        XCTAssertEqual(
            items(from: "- 周会纪要", clipboard: "纪要正文"),
            ["周会纪要\(AINoteExport.fieldSeparator)纪要正文"]
        )
    }

    func testKeepsTitleAndBodyWhenTheyMatch() {
        XCTAssertEqual(
            items(from: "买牛奶", clipboard: "买牛奶"),
            ["买牛奶\(AINoteExport.fieldSeparator)买牛奶"]
        )
    }

    func testTruncatesLongTitle() {
        let title = String(repeating: "纪", count: 50)
        let items = items(from: title, clipboard: "正文")
        XCTAssertEqual(items.count, 1)
        let fields = items[0].components(separatedBy: AINoteExport.fieldSeparator)
        XCTAssertEqual(fields.count, 2)
        XCTAssertEqual(fields[0].count, AINoteExport.maximumTitleLength)
        XCTAssertEqual(fields[1], "正文")
    }

    func testWholeClipboardEchoFallsBack() {
        let source = String(repeating: "这是一段很长的会议纪要内容，包含许多句子。", count: 4)
        let items = items(from: source, clipboard: source)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].hasPrefix("8月13日 · "))
        XCTAssertTrue(items[0].hasSuffix("\(AINoteExport.fieldSeparator)\(source)"))
    }

    func testPromptAsksForTitleOnly() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.saveToNotesID,
            locale: "zh",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            now: now
        )
        XCTAssertTrue(prompt.contains("标题"))
        XCTAssertTrue(prompt.contains("不要输出正文"))
        XCTAssertTrue(prompt.contains("不要改写"))
    }

    func testEnglishPromptAsksForTitleOnly() {
        let prompt = AIClipboardSkillCatalog.instruction(
            skillID: AIClipboardSkillCatalog.saveToNotesID,
            locale: "en",
            translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId,
            now: now
        )
        XCTAssertTrue(prompt.contains("title"))
        XCTAssertTrue(prompt.contains("do not output the body"))
    }

    private func items(
        from answer: String,
        clipboard: String?,
        locale: String = "zh"
    ) -> [String] {
        AINoteExport.items(
            from: answer,
            sourceClipboard: clipboard,
            now: now,
            locale: locale,
            calendar: calendar
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
