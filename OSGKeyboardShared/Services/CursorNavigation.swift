// CursorNavigation.swift
// OSGKeyboard · Shared
//
// Pure helpers for moving the text caret from the keyboard extension.
// Horizontal moves are character-accurate. Vertical moves jump between
// *visual* lines — hard `\n` breaks and soft wraps.
//
// First-principles note: a keyboard extension only sees a bounded text
// window (`documentContext{Before,After}Input`) and can only actuate via
// `adjustTextPosition(byCharacterOffset:)`. It has NO access to the host
// field's font, width, or caret rect, so soft-wrap positions are
// fundamentally unknowable and must be *estimated*. We reduce the visible
// error two ways: (1) exact handling of hard `\n`; (2) an injectable
// per-character width so the extension can feed real font metrics (killing
// the i-vs-W column drift that a fixed 1/2 table causes). The wrap width
// itself stays a calibrated estimate.

import Foundation
import CoreGraphics

public enum CursorNavigation {

    /// Advance width of a single character, in an arbitrary but consistent
    /// unit (points when backed by real font metrics; abstract "units" for
    /// the built-in default). Must be paired with a `lineWidth` in the same
    /// unit.
    public typealias CharacterWidth = @Sendable (Character) -> CGFloat

    // MARK: - Layout config

    /// Describes how text wraps into visual lines. `lineWidth` and the values
    /// returned by `widthOf` must share the same unit.
    public struct VisualLineLayoutConfig: Sendable {
        /// Wrap threshold: max total width of one visual line.
        public let lineWidth: CGFloat
        /// Per-character advance width provider.
        public let widthOf: CharacterWidth

        public init(
            lineWidth: CGFloat,
            widthOf: @escaping CharacterWidth = CursorNavigation.defaultDisplayWidth
        ) {
            self.lineWidth = max(1, lineWidth)
            self.widthOf = widthOf
        }

        /// Conservative default when no field width is known.
        public static let fallback = VisualLineLayoutConfig(lineWidth: 44)
    }

    // MARK: - Public API

    /// Legacy logical column (chars since last `\n`). Kept for tests.
    public static func column(before: String?) -> Int {
        guard let before, !before.isEmpty else { return 0 }
        if let lastNewline = before.lastIndex(of: "\n") {
            return before.distance(from: before.index(after: lastNewline), to: before.endIndex)
        }
        return before.count
    }

    /// Display-column offset (in `widthOf` units) on the current visual line.
    public static func visualDisplayColumn(
        before: String?,
        after: String?,
        config: VisualLineLayoutConfig
    ) -> CGFloat {
        let text = mergedContext(before: before, after: after)
        let cursor = before?.count ?? 0
        let layout = VisualLineLayout(text: text, config: config)
        let lineStart = layout.lineStart(containing: cursor)
        return layout.width(from: lineStart, to: cursor)
    }

    /// One visual line up. Returns caret offset and the display column to
    /// keep sticky for the rest of this vertical drag.
    public static func visualLineUpOffset(
        before: String?,
        after: String?,
        preferredDisplayColumn: CGFloat?,
        config: VisualLineLayoutConfig
    ) -> (offset: Int, stickyColumn: CGFloat)? {
        let text = mergedContext(before: before, after: after)
        let cursor = before?.count ?? 0
        let layout = VisualLineLayout(text: text, config: config)

        guard let currentLine = layout.lineIndex(containing: cursor), currentLine > 0 else {
            return nil
        }

        let sticky = preferredDisplayColumn
            ?? layout.width(from: layout.lineStarts[currentLine], to: cursor)
        let previousStart = layout.lineStarts[currentLine - 1]
        let previousEnd = layout.lineStarts[currentLine]
        let target = layout.offset(
            onLineStartingAt: previousStart,
            lineEndingBefore: previousEnd,
            displayColumn: sticky
        )
        let offset = target - cursor
        guard offset != 0 else { return nil }
        return (offset, sticky)
    }

    /// One visual line down.
    public static func visualLineDownOffset(
        before: String?,
        after: String?,
        preferredDisplayColumn: CGFloat?,
        config: VisualLineLayoutConfig
    ) -> (offset: Int, stickyColumn: CGFloat)? {
        let text = mergedContext(before: before, after: after)
        let cursor = before?.count ?? 0
        let layout = VisualLineLayout(text: text, config: config)

        guard let currentLine = layout.lineIndex(containing: cursor) else { return nil }
        guard currentLine + 1 < layout.lineStarts.count else { return nil }

        let sticky = preferredDisplayColumn
            ?? layout.width(from: layout.lineStarts[currentLine], to: cursor)
        let nextStart = layout.lineStarts[currentLine + 1]
        let nextEnd = currentLine + 2 < layout.lineStarts.count
            ? layout.lineStarts[currentLine + 2]
            : text.count
        let target = layout.offset(
            onLineStartingAt: nextStart,
            lineEndingBefore: nextEnd,
            displayColumn: sticky
        )
        let offset = target - cursor
        guard offset != 0 else { return nil }
        return (offset, sticky)
    }

    // MARK: - Default width table

    /// Crude fallback advance width: wide scripts count double, everything
    /// else single. Used by tests and when real metrics are unavailable.
    public static func defaultDisplayWidth(_ character: Character) -> CGFloat {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        if character == "\n" { return 0 }
        if character == "\t" { return 4 }
        if isWide(scalar) { return 2 }
        return 1
    }

    private static func isWide(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return (0x1100...0x115F).contains(value) // Hangul Jamo
            || (0x2E80...0xA4CF).contains(value) // CJK radicals, symbols, bopomofo, yi
            || (0xAC00...0xD7A3).contains(value) // Hangul syllables
            || (0xF900...0xFAFF).contains(value) // CJK compatibility
            || (0xFE10...0xFE1F).contains(value) // vertical forms
            || (0xFE30...0xFE6F).contains(value) // CJK compatibility forms
            || (0xFF00...0xFF60).contains(value) // fullwidth
            || (0xFFE0...0xFFE6).contains(value) // fullwidth symbols
            || (0x20000...0x2FFFF).contains(value) // CJK extension planes
            || (0x30000...0x3FFFF).contains(value)
    }

    // MARK: - Internals

    private static func mergedContext(before: String?, after: String?) -> String {
        (before ?? "") + (after ?? "")
    }

    // MARK: - Visual line layout

    struct VisualLineLayout {
        let text: String
        let widthOf: CharacterWidth
        let lineStarts: [Int]

        init(text: String, config: VisualLineLayoutConfig) {
            self.text = text
            self.widthOf = config.widthOf
            self.lineStarts = Self.computeLineStarts(
                in: text,
                maxWidth: config.lineWidth,
                widthOf: config.widthOf
            )
        }

        func lineIndex(containing offset: Int) -> Int? {
            guard !lineStarts.isEmpty else { return nil }
            for index in lineStarts.indices.reversed() where offset >= lineStarts[index] {
                return index
            }
            return nil
        }

        func lineStart(containing offset: Int) -> Int {
            lineIndex(containing: offset).map { lineStarts[$0] } ?? 0
        }

        func width(from start: Int, to end: Int) -> CGFloat {
            guard start < end, end <= text.count else { return 0 }
            let startIndex = text.index(text.startIndex, offsetBy: start)
            let endIndex = text.index(text.startIndex, offsetBy: end)
            var total: CGFloat = 0
            var index = startIndex
            while index < endIndex {
                total += widthOf(text[index])
                index = text.index(after: index)
            }
            return total
        }

        func offset(
            onLineStartingAt lineStart: Int,
            lineEndingBefore lineEnd: Int,
            displayColumn: CGFloat
        ) -> Int {
            guard lineStart <= lineEnd, lineEnd <= text.count else { return lineStart }
            let startIndex = text.index(text.startIndex, offsetBy: lineStart)
            let endIndex = text.index(text.startIndex, offsetBy: lineEnd)
            var total: CGFloat = 0
            var index = startIndex
            while index < endIndex {
                let advance = widthOf(text[index])
                if total + advance > displayColumn { break }
                total += advance
                index = text.index(after: index)
            }
            return text.distance(from: text.startIndex, to: index)
        }

        private static func computeLineStarts(
            in text: String,
            maxWidth: CGFloat,
            widthOf: CharacterWidth
        ) -> [Int] {
            guard !text.isEmpty else { return [0] }

            var starts: [Int] = [0]
            var lineWidth: CGFloat = 0
            var lineStart = text.startIndex
            var lastBreak: String.Index?

            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]

                if character == "\n" {
                    let next = text.index(after: index)
                    let nextOffset = text.distance(from: text.startIndex, to: next)
                    if starts.last != nextOffset {
                        starts.append(nextOffset)
                    }
                    lineStart = next
                    lineWidth = 0
                    lastBreak = nil
                    index = next
                    continue
                }

                let advance = widthOf(character)
                if character == " " || character == "\t" {
                    lastBreak = index
                }

                if lineWidth + advance > maxWidth, index > lineStart {
                    let breakIndex: String.Index
                    if let lastBreak, lastBreak > lineStart {
                        breakIndex = text.index(after: lastBreak)
                    } else {
                        breakIndex = index
                    }
                    let breakOffset = text.distance(from: text.startIndex, to: breakIndex)
                    if starts.last != breakOffset {
                        starts.append(breakOffset)
                    }
                    lineStart = breakIndex
                    lineWidth = 0
                    lastBreak = nil
                    if breakIndex == index {
                        lineWidth = advance
                        index = text.index(after: index)
                    }
                    continue
                }

                lineWidth += advance
                index = text.index(after: index)
            }

            return starts
        }
    }
}

#if canImport(UIKit)
import UIKit

/// Real-font per-character advance widths (in points) for cursor visual-line
/// navigation. Caches measurements so repeated drag samples are cheap.
///
/// Absolute values assume a ~17 pt body font; only the *ratios* between
/// glyphs (and between a glyph and the field width) matter for column
/// fidelity, so a reference font is sufficient to eliminate the fixed-width
/// column drift.
///
/// Not actor-isolated on purpose: the width closure is invoked synchronously
/// from the nonisolated `CursorNavigation` layout code. A lock guards the
/// cache so `@unchecked Sendable` is safe.
public final class CursorGlyphMetrics: @unchecked Sendable {
    public static let shared = CursorGlyphMetrics()

    private let font = UIFont.systemFont(ofSize: 17)
    private let lock = NSLock()
    private var cache: [Character: CGFloat] = [:]

    public init() {}

    public func width(of character: Character) -> CGFloat {
        if character == "\n" { return 0 }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[character] { return cached }
        let measured = (String(character) as NSString)
            .size(withAttributes: [.font: font])
            .width
        let width = measured > 0 ? measured : font.pointSize * 0.5
        cache[character] = width
        return width
    }
}
#endif
