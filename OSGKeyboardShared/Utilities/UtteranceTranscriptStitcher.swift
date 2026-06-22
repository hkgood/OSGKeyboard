// UtteranceTranscriptStitcher.swift
// OSGKeyboard · Shared
//
// Orders pipelined chunk transcripts and merges overlap at boundaries.

import Foundation

public struct UtteranceTranscriptStitcher: Sendable {
    private var segments: [(index: Int, text: String)] = []

    public init() {}

    public mutating func append(index: Int, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = segments.firstIndex(where: { $0.index == index }) {
            segments[existing].text = trimmed
        } else {
            segments.append((index, trimmed))
            segments.sort { $0.index < $1.index }
        }
    }

    public func composed() -> String {
        guard let first = segments.first else { return "" }
        var result = first.text
        for segment in segments.dropFirst() {
            result = Self.mergeWithOverlap(previous: result, next: segment.text)
        }
        return result
    }

    /// Merge `next` onto `previous`, dropping duplicated suffix/prefix overlap.
    public static func mergeWithOverlap(previous: String, next: String) -> String {
        let trimmedNext = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNext.isEmpty else { return previous }
        guard !previous.isEmpty else { return trimmedNext }

        // Character-granular probe — works for CJK without word boundaries.
        let prevChars = Array(previous)
        let nextChars = Array(trimmedNext)
        let maxProbe = min(64, prevChars.count, nextChars.count)
        if maxProbe > 0 {
            for length in stride(from: maxProbe, through: 1, by: -1) {
                let suffix = prevChars.suffix(length)
                let prefix = nextChars.prefix(length)
                if suffix.elementsEqual(prefix) {
                    return previous + String(nextChars.dropFirst(length))
                }
            }
        }

        // Punctuation-insensitive CJK overlap (e.g. "很好，" + "很好继续").
        let normalizedPrev = normalizeForOverlap(previous)
        let normalizedNext = normalizeForOverlap(trimmedNext)
        let nPrev = Array(normalizedPrev)
        let nNext = Array(normalizedNext)
        let normProbe = min(64, nPrev.count, nNext.count)
        if normProbe > 0 {
            for length in stride(from: normProbe, through: 2, by: -1) {
                if nPrev.suffix(length).elementsEqual(nNext.prefix(length)) {
                    // Map normalized overlap length back to raw `next` drop count.
                    let drop = overlapDropCount(in: trimmedNext, normalizedPrefixLength: length)
                    return previous + String(trimmedNext.dropFirst(drop))
                }
            }
        }

        // English / spaced languages.
        let maxWordProbe = min(6, previous.split(separator: " ").count, trimmedNext.split(separator: " ").count)
        if maxWordProbe > 0 {
            let prevWords = previous.split(separator: " ", omittingEmptySubsequences: true)
            let nextWords = trimmedNext.split(separator: " ", omittingEmptySubsequences: true)
            for wordCount in stride(from: maxWordProbe, through: 1, by: -1) {
                if prevWords.suffix(wordCount).elementsEqual(nextWords.prefix(wordCount)) {
                    let mergedPrefix = nextWords.dropFirst(wordCount).joined(separator: " ")
                    if mergedPrefix.isEmpty { return previous }
                    if previous.last == " " || previous.last == "\n" {
                        return previous + mergedPrefix
                    }
                    return previous + " " + mergedPrefix
                }
            }
        }

        return DictationTextComposer.compose(anchor: previous, live: trimmedNext)
    }

    private static func normalizeForOverlap(_ text: String) -> String {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.map { Character($0) }.reduce(into: "") { $0.append($1) }
    }

    /// How many raw characters to drop from `next` given a normalized-prefix overlap length.
    private static func overlapDropCount(in next: String, normalizedPrefixLength: Int) -> Int {
        var normalizedCount = 0
        var rawIndex = next.startIndex
        while rawIndex < next.endIndex, normalizedCount < normalizedPrefixLength {
            let scalar = next[rawIndex]
            if !scalar.isWhitespace, !scalar.isPunctuation {
                normalizedCount += 1
            }
            rawIndex = next.index(after: rawIndex)
        }
        return next.distance(from: next.startIndex, to: rawIndex)
    }
}
