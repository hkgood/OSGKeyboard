// DictationTextComposer.swift
// OSGKeyboard · Shared
//
// Merges pre-dictation anchor text with a live cumulative transcript.

import Foundation

public enum DictationTextComposer {
    /// Combine text that existed before dictation with the current live transcript.
    public static func compose(anchor: String, live: String) -> String {
        let trimmed = live.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return anchor }
        if anchor.isEmpty { return trimmed }
        if let merged = mergeOverlapping(anchor: anchor, live: trimmed) {
            return merged
        }
        if shouldConcatenateWithoutSpace(anchor: anchor, live: trimmed) {
            return anchor + trimmed
        }
        if anchor.last == " " || anchor.last == "\n" { return anchor + trimmed }
        return anchor + " " + trimmed
    }

    /// Drop duplicated suffix/prefix overlap before falling back to spaced composition.
    /// This catches progressive ASR revisions such as "可用性" + "可用性已经".
    private static func mergeOverlapping(anchor: String, live: String) -> String? {
        let anchorChars = Array(anchor)
        let liveChars = Array(live)
        let maxProbe = min(64, anchorChars.count, liveChars.count)
        if maxProbe > 0 {
            for length in stride(from: maxProbe, through: 2, by: -1) {
                if anchorChars.suffix(length).elementsEqual(liveChars.prefix(length)) {
                    return anchor + String(liveChars.dropFirst(length))
                }
            }
        }

        let normalizedAnchor = normalizeForOverlap(anchor)
        let normalizedLive = normalizeForOverlap(live)
        let anchorNormChars = Array(normalizedAnchor)
        let liveNormChars = Array(normalizedLive)
        let normProbe = min(64, anchorNormChars.count, liveNormChars.count)
        if normProbe > 0 {
            for length in stride(from: normProbe, through: 3, by: -1) {
                if anchorNormChars.suffix(length).elementsEqual(liveNormChars.prefix(length)) {
                    let drop = rawDropCount(in: live, normalizedPrefixLength: length)
                    return anchor + String(live.dropFirst(drop))
                }
            }
        }

        return nil
    }

    private static func shouldConcatenateWithoutSpace(anchor: String, live: String) -> Bool {
        guard let last = anchor.unicodeScalars.last,
              let first = live.unicodeScalars.first else {
            return false
        }
        return isCJK(last) && isCJK(first)
    }

    static func normalizeForOverlap(_ text: String) -> String {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.map { Character($0) }.reduce(into: "") { $0.append($1) }
    }

    private static func rawDropCount(in text: String, normalizedPrefixLength: Int) -> Int {
        var normalizedCount = 0
        var rawIndex = text.startIndex
        while rawIndex < text.endIndex, normalizedCount < normalizedPrefixLength {
            let character = text[rawIndex]
            if !character.isWhitespace, !character.isPunctuation {
                normalizedCount += 1
            }
            rawIndex = text.index(after: rawIndex)
        }
        return text.distance(from: text.startIndex, to: rawIndex)
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}
