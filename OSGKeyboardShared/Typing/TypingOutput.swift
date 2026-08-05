// TypingOutput.swift
// OSGKeyboard · Shared
//
// Unified mutation the typing UI applies to UITextDocumentProxy.
// English autocorrect / completion need multi-delete + insert; Chinese
// mostly inserts or issues a single backspace sentinel.

import Foundation

/// Text mutation produced by one typing action.
public struct TypingOutput: Equatable, Sendable {
    /// How many `deleteBackward` calls to issue before inserting.
    public var deleteCount: Int
    /// Text to insert after deletions (may be empty).
    public var text: String

    public init(deleteCount: Int = 0, text: String = "") {
        self.deleteCount = deleteCount
        self.text = text
    }

    public static let none = TypingOutput()

    public static func insert(_ text: String) -> TypingOutput {
        TypingOutput(deleteCount: 0, text: text)
    }

    public static let backspace = TypingOutput(deleteCount: 1, text: "")

    public static func replace(deleteCount: Int, with text: String) -> TypingOutput {
        TypingOutput(deleteCount: deleteCount, text: text)
    }

    public var isEmpty: Bool {
        deleteCount == 0 && text.isEmpty
    }
}
