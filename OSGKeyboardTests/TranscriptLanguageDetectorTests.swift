import XCTest
@testable import OSGKeyboardShared

final class TranscriptLanguageDetectorTests: XCTestCase {
    func testChineseAndMixedInputPreferChineseGuidance() {
        XCTAssertTrue(TranscriptLanguageDetector.prefersChineseGuidance("今天开会讨论 roadmap"))
        XCTAssertTrue(TranscriptLanguageDetector.prefersChineseGuidance("把 PRD 发给 Ali review"))
    }

    func testEnglishJapaneseAndKoreanDoNotPreferChineseGuidance() {
        XCTAssertFalse(TranscriptLanguageDetector.prefersChineseGuidance("ship it tomorrow"))
        XCTAssertFalse(TranscriptLanguageDetector.prefersChineseGuidance("こんにちは"))
        XCTAssertFalse(TranscriptLanguageDetector.prefersChineseGuidance("안녕하세요"))
    }

    func testNumbersHaveNoScriptSignal() {
        XCTAssertEqual(TranscriptLanguageDetector.cjkRatio("12345"), 0)
        XCTAssertEqual(TranscriptLanguageDetector.cjkRatio(""), 0)
    }

    func testHanRangeBoundariesRemainStable() {
        let hanScalars = [0x3400, 0x4DBF, 0x4E00, 0x9FFF, 0xF900, 0xFAFF]
            .compactMap(UnicodeScalar.init)
            .map(String.init)
            .joined()
        XCTAssertEqual(TranscriptLanguageDetector.cjkRatio(hanScalars), 1)
        XCTAssertTrue(RimePinyinAnnotator.containsCJK(hanScalars))
        XCTAssertFalse(PersonalDictionary.isEnglishTypingHotword("产品GPT"))
    }

    func testKanaHangulAndFullwidthLatinAreNotHanIdeographs() {
        let nonHan = "こんにちは안녕하세요Ａ"
        XCTAssertEqual(TranscriptLanguageDetector.cjkRatio(nonHan), 0)
        XCTAssertFalse(RimePinyinAnnotator.containsCJK(nonHan))
        XCTAssertTrue(PersonalDictionary.isEnglishTypingHotword("ＧPT"))
    }

    func testJapaneseTextContainingHanKeepsCurrentHanSignal() {
        XCTAssertTrue(TranscriptLanguageDetector.prefersChineseGuidance("日本語"))
    }
}
