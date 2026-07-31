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
}
