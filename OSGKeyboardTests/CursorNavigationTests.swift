// CursorNavigationTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class CursorNavigationTests: XCTestCase {

    /// Uses the built-in 1/2-unit width table. `lineWidth` is therefore in
    /// "units" (≈ Latin characters) for these tests.
    private func config(lineWidth: CGFloat) -> CursorNavigation.VisualLineLayoutConfig {
        CursorNavigation.VisualLineLayoutConfig(lineWidth: lineWidth)
    }

    func testColumnOnFirstLine() {
        XCTAssertEqual(CursorNavigation.column(before: "hello"), 5)
        XCTAssertEqual(CursorNavigation.column(before: nil), 0)
    }

    func testColumnAfterNewline() {
        XCTAssertEqual(CursorNavigation.column(before: "hello\nwor"), 3)
    }

    func testDefaultDisplayWidthLatinAndCJK() {
        XCTAssertEqual(CursorNavigation.defaultDisplayWidth("a"), 1)
        XCTAssertEqual(CursorNavigation.defaultDisplayWidth("中"), 2)
        XCTAssertEqual(CursorNavigation.defaultDisplayWidth("\n"), 0)
    }

    func testVisualLineDownAcrossSoftWrap() {
        // 20 Latin chars, wrap at 16 → line0 [0,16), line1 [16,20).
        let text = String(repeating: "a", count: 20)
        let before = String(text.prefix(8))
        let after = String(text.suffix(12))

        let result = CursorNavigation.visualLineDownOffset(
            before: before,
            after: after,
            preferredDisplayColumn: nil,
            config: config(lineWidth: 16)
        )
        XCTAssertNotNil(result)
        // Sticky column 8; line1 only has 4 units → clamp to its end.
        XCTAssertEqual(result?.offset, 12)
    }

    func testVisualLineDownToShorterWrappedLineClampsToEnd() {
        // Caret at col 15 (clearly on line0); line1 has only 4 chars.
        let text = String(repeating: "a", count: 20)
        let before = String(text.prefix(15))
        let after = String(text.suffix(5))

        let result = CursorNavigation.visualLineDownOffset(
            before: before,
            after: after,
            preferredDisplayColumn: 15,
            config: config(lineWidth: 16)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offset, 5)
        XCTAssertEqual(result?.stickyColumn, 15)
    }

    func testVisualLineUpAcrossSoftWrap() {
        let text = String(repeating: "a", count: 20)
        let before = String(text.prefix(18))
        let after = String(text.suffix(2))

        let result = CursorNavigation.visualLineUpOffset(
            before: before,
            after: after,
            preferredDisplayColumn: 8,
            config: config(lineWidth: 16)
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.offset, -10)
    }

    func testVisualLineDownAcrossHardNewline() {
        let before = "hello\nwor"
        let after = "ld\nfoo"

        let result = CursorNavigation.visualLineDownOffset(
            before: before,
            after: after,
            preferredDisplayColumn: nil,
            config: config(lineWidth: 100)
        )
        XCTAssertNotNil(result)
        // "hello\nworld\nfoo" — caret before "ld"; column 3 lands after "foo".
        XCTAssertEqual(result?.offset, 6)
    }

    func testVisualLineDownPreservesStickyColumnOnLongerNextLine() {
        let before = "hello\nwor"
        let after = "ld\nfoobarbaz"

        let result = CursorNavigation.visualLineDownOffset(
            before: before,
            after: after,
            preferredDisplayColumn: 5,
            config: config(lineWidth: 100)
        )
        XCTAssertNotNil(result)
        // "ld\n" (3) + column 5 on "foobarbaz" = 8 total from cursor.
        XCTAssertEqual(result?.offset, 8)
        XCTAssertEqual(result?.stickyColumn, 5)
    }

    func testVisualLineUpOnFirstLineReturnsNil() {
        XCTAssertNil(
            CursorNavigation.visualLineUpOffset(
                before: "hello",
                after: " world",
                preferredDisplayColumn: nil,
                config: config(lineWidth: 100)
            )
        )
    }

    func testVisualLineDownWithNoFollowingTextReturnsNil() {
        XCTAssertNil(
            CursorNavigation.visualLineDownOffset(
                before: "hello",
                after: nil,
                preferredDisplayColumn: nil,
                config: config(lineWidth: 100)
            )
        )
        XCTAssertNil(
            CursorNavigation.visualLineDownOffset(
                before: "hello",
                after: "",
                preferredDisplayColumn: nil,
                config: config(lineWidth: 100)
            )
        )
    }
}
