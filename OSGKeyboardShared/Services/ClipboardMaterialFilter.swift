// ClipboardMaterialFilter.swift
// OSGKeyboard · Shared
//
// Pure eligibility rules for clipboard-command mode (plan §4 R0–R6 content rules).
// Runtime gates (secure field, Full Access) live in the keyboard extension.

import Foundation

public enum ClipboardMaterialFilter: Sendable {

    public static let minimumLength = 15
    public static let maxSnapshotLength = 3_000
    public static let longPressDuration: TimeInterval = 0.45
    /// After the host confirms real capture, keep recording at least this long
    /// before honoring an explicit stop tap (avoids near-silent cold-start tails).
    public static let minimumRecordingAfterHostConfirm: TimeInterval = 0.70
    /// How long a clipboard-command failure tip stays above the mic.
    public static let failureHintDuration: TimeInterval = 2.5

    public enum Rejection: String, Equatable, Sendable {
        case empty
        case phoneOrNumeric
        case emojiOrSymbolOnly
        case verificationCode
        case tooShort
        case repetitiveSpam
    }

    public enum Verdict: Equatable, Sendable {
        case eligible(String)
        case rejected(Rejection)
    }

    /// Evaluate trimmed clipboard text for command-mode entry.
    public static func evaluate(_ raw: String) -> Verdict {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .rejected(.empty) }

        if isPhoneOrNumeric(trimmed) { return .rejected(.phoneOrNumeric) }
        if isEmojiOrSymbolOnly(trimmed) { return .rejected(.emojiOrSymbolOnly) }
        if isVerificationCode(trimmed) { return .rejected(.verificationCode) }
        if trimmed.count < minimumLength { return .rejected(.tooShort) }
        if isRepetitiveSpam(trimmed) { return .rejected(.repetitiveSpam) }

        return .eligible(truncateSnapshot(trimmed))
    }

    /// Wire / LLM snapshot cap (plan: 3000 grapheme clusters).
    public static func truncateSnapshot(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxSnapshotLength else { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxSnapshotLength)
        return String(trimmed[..<end])
    }

    // MARK: - Rules

    /// R1: whole string looks like a phone / order number after stripping whitespace.
    private static func isPhoneOrNumeric(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789-+()")
        guard compact.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        return compact.contains { $0.isNumber }
    }

    /// R2: no letter, CJK, or digit — only emoji / punctuation / symbols.
    private static func isEmojiOrSymbolOnly(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return false }
        return !compact.contains { characterHasLetterOrNumber($0) }
    }

    /// R3: length 4…8, alphanumeric only, mixed letters + digits.
    private static func isVerificationCode(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard (4...8).contains(compact.count) else { return false }
        guard compact.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        let hasLetter = compact.contains(where: \.isLetter)
        let hasDigit = compact.contains(where: \.isNumber)
        return hasLetter && hasDigit
    }

    /// R5: length ≥ 15, ≤2 distinct characters, one char ≥ 80% share.
    private static func isRepetitiveSpam(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.count >= minimumLength else { return false }

        var counts: [Character: Int] = [:]
        for ch in compact {
            counts[ch, default: 0] += 1
        }
        guard counts.count <= 2 else { return false }
        let maxShare = counts.values.max() ?? 0
        return Double(maxShare) / Double(compact.count) >= 0.80
    }

    private static func characterHasLetterOrNumber(_ character: Character) -> Bool {
        if character.isLetter || character.isNumber { return true }
        // CJK ideographs / kana counted as “letter-like” content for R2.
        for scalar in character.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF, // CJK Unified
                 0x3400...0x4DBF, // CJK Ext A
                 0x3040...0x30FF, // Hiragana / Katakana
                 0xAC00...0xD7AF: // Hangul
                return true
            default:
                continue
            }
        }
        return false
    }
}
