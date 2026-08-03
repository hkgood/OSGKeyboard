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
    func rows(for page: TypingKeyPage, shiftActive: Bool) -> [[String]]
}

/// Standard phone QWERTY + 123 + light symbols (NanoMouse / system-like).
public struct StandardTypingLayout: TypingLayoutProviding {
    public init() {}

    public func rows(for page: TypingKeyPage, shiftActive: Bool) -> [[String]] {
        switch page {
        case .letters:
            let upper = shiftActive
            let map: (String) -> String = { upper ? $0.uppercased() : $0 }
            return [
                ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"].map(map),
                ["a", "s", "d", "f", "g", "h", "j", "k", "l"].map(map),
                ["⇧", "z", "x", "c", "v", "b", "n", "m", "⌫"].map { $0.count == 1 ? map($0) : $0 }
            ]
        case .numbers:
            return [
                ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
                ["#+=", ".", ",", "?", "!", "'", "⌫"]
            ]
        case .symbols:
            return [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
                ["123", ".", ",", "?", "!", "'", "⌫"],
                ["，", "。", "、", "？", "！", "：", "；"]
            ]
        }
    }
}
