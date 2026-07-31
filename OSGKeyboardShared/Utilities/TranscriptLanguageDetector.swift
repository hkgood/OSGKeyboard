// TranscriptLanguageDetector.swift
// OSGKeyboard · Shared
//
// Lightweight script detection for choosing the language of LLM guidance.
// This intentionally does not attempt full language identification.

import Foundation

public enum TranscriptLanguageDetector: Sendable {
    /// Han characters as a share of non-whitespace, non-punctuation characters.
    public static func cjkRatio(_ text: String) -> Double {
        var hanCount = 0
        var meaningfulCount = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.punctuationCharacters.contains(scalar)
                || CharacterSet.symbols.contains(scalar) {
                continue
            }
            meaningfulCount += 1
            if isHan(scalar) {
                hanCount += 1
            }
        }

        guard meaningfulCount > 0 else { return 0 }
        return Double(hanCount) / Double(meaningfulCount)
    }

    /// Mixed Chinese/English transcripts should still receive Chinese guidance.
    public static func prefersChineseGuidance(_ text: String) -> Bool {
        cjkRatio(text) >= 0.15
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}
