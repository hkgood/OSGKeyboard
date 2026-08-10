// ClipboardHistoryPolicy.swift
// OSGKeyboard · Shared
//
// Pure rules for accepting clipboard text and simple English/whitespace tokens.

import Foundation

public enum ClipboardHistoryPolicy: Sendable {
    public static let maxEntries = 15
    /// Reject short all-digit strings (OTP / verification-code shaped).
    public static let otpDigitMaxLength = 8

    /// Returns trimmed text when it should be stored; otherwise `nil`.
    public static func acceptedText(from raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksLikeOTP(trimmed) { return nil }
        return trimmed
    }

    /// Pure digits (optionally with spaces/dashes) of length 4…8 → treat as OTP.
    public static func looksLikeOTP(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        guard digits.count == text.filter({ !$0.isWhitespace && $0 != "-" }).count else {
            return false
        }
        return (4...otpDigitMaxLength).contains(digits.count)
    }

    /// Simple whitespace / ASCII-punctuation split for English-ish snippets.
    public static func whitespaceTokens(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            // Skip pure CJK-only single chars that aren't useful as chips.
            .filter { token in
                token.count > 1 || token.unicodeScalars.contains { $0.isASCII }
            }
    }

    /// Merge `incoming` onto `existing` (newest first), dedupe by exact text.
    public static func merging(
        incoming: ClipboardHistoryEntry,
        into existing: [ClipboardHistoryEntry],
        limit: Int = maxEntries
    ) -> [ClipboardHistoryEntry] {
        var next = existing.filter { $0.text != incoming.text }
        next.insert(incoming, at: 0)
        if next.count > limit {
            next = Array(next.prefix(limit))
        }
        return next
    }
}
