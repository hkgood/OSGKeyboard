// TypingLayoutProviding.swift
// OSGKeyboard · Shared
//
// Phase 2 escape hatch: replace the in-repo SwiftUI key shell with a
// KeyboardKit-based (or other) layout without changing the engine bridge.

import Foundation

/// Page shown by the typing key shell.
public enum TypingKeyPage: String, CaseIterable, Sendable {
    case letters
    case numbers
    case symbols
}

/// Abstraction over “which characters the current page shows”.
/// The Phase 1 SwiftUI keyboard reads this; a future Kit-backed shell
/// can feed the same consumer.
public protocol TypingLayoutProviding: Sendable {
    func rows(
        for page: TypingKeyPage,
        language: TypingInputLanguage,
        shiftActive: Bool
    ) -> [[String]]
}

/// Phone QWERTY + 123 / #+= pages aligned with iOS system keyboards
/// (English US and Simplified Chinese Pinyin).
public struct StandardTypingLayout: TypingLayoutProviding {
    public init() {}

    public func rows(
        for page: TypingKeyPage,
        language: TypingInputLanguage,
        shiftActive: Bool
    ) -> [[String]] {
        switch page {
        case .letters:
            return letterRows(shiftActive: shiftActive)
        case .numbers:
            return language == .chinese ? chineseNumberRows : englishNumberRows
        case .symbols:
            return language == .chinese ? chineseSymbolRows : englishSymbolRows
        }
    }

    // MARK: - Letters (shared)

    private func letterRows(shiftActive: Bool) -> [[String]] {
        let upper = shiftActive
        let map: (String) -> String = { upper ? $0.uppercased() : $0 }
        return [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"].map(map),
            ["a", "s", "d", "f", "g", "h", "j", "k", "l"].map(map),
            ["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"].map { $0.count == 1 ? map($0) : $0 }
        ]
    }

    // MARK: - English (iOS US)

    /// iOS English US · Numbers
    private var englishNumberRows: [[String]] {
        [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
            ["#+=", ".", ",", "?", "!", "'", "⌫"]
        ]
    }

    /// iOS English US · Symbols
    private var englishSymbolRows: [[String]] {
        [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
            ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
            ["123", ".", ",", "?", "!", "'", "⌫"]
        ]
    }

    // MARK: - Chinese (iOS 简体拼音)

    /// iOS Simplified Chinese · Numbers (fullwidth punctuation where system uses it)
    private var chineseNumberRows: [[String]] {
        [
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
            // System 123 page uses curly double quotes “ ” (not corner brackets).
            ["-", "/", "：", "；", "（", "）", "￥", "@", "“", "”"],
            ["#+=", "。", "，", "、", "？", "！", ".", "⌫"]
        ]
    }

    /// iOS Simplified Chinese · Symbols
    private var chineseSymbolRows: [[String]] {
        [
            // 「」 live on #+= so they remain reachable after numbers use “ ”.
            ["【", "】", "「", "」", "#", "%", "^", "*", "+", "="],
            ["_", "\\", "|", "~", "《", "》", "€", "£", "¥", "·"],
            ["123", "。", "，", "、", "？", "！", ".", "⌫"]
        ]
    }
}
