// UtteranceTranscriptStitcher.swift
// OSGKeyboard · Shared
//
// Orders pipelined chunk transcripts and merges overlap at boundaries.

import Foundation

public struct UtteranceTranscriptStitcher: Sendable {
    private var segments: [(index: Int, text: String, trailingPauseSeconds: Double)] = []

    public init() {}

    public mutating func append(
        index: Int,
        text: String,
        trailingPauseSeconds: Double = 0
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = segments.firstIndex(where: { $0.index == index }) {
            segments[existing].text = trimmed
            segments[existing].trailingPauseSeconds = trailingPauseSeconds
        } else {
            segments.append((index, trimmed, trailingPauseSeconds))
            segments.sort { $0.index < $1.index }
        }
    }

    /// Drop the highest-index segment (used when re-transcribing a merged tail chunk).
    public mutating func removeLastSegment() {
        guard !segments.isEmpty else { return }
        segments.removeLast()
    }

    public func composed() -> String {
        guard let first = segments.first else { return "" }
        var result = first.text
        for segment in segments.dropFirst() {
            result = Self.mergeWithOverlap(previous: result, next: segment.text)
        }
        return result
    }

    /// Prefer overlap-aware merge, but fall back to naive join when dedup would drop real content.
    public func composedSafely() -> String {
        let merged = composed()
        guard segments.count >= 2 else { return merged }
        let naive = segments.map(\.text).joined(separator: " ")
        if merged.count + 16 < naive.count {
            FlowPipelineDiagnostics.logStitcherSafeFallback(
                naiveLength: naive.count,
                mergedLength: merged.count
            )
            return naive
        }
        return merged
    }

    /// Final text for LLM processing only. Partial preview continues to use
    /// `composedSafely()` and therefore never exposes internal markers.
    public func composedWithPauseMarks(threshold: Double = 0.45) -> String {
        guard let first = segments.first else { return "" }
        let safePlain = composedSafely()
        let mergedPlain = composed()
        if safePlain != mergedPlain {
            return naiveWithPauseMarks(threshold: threshold)
        }

        var plain = first.text
        var marked = first.text
        var previous = first
        for segment in segments.dropFirst() {
            let nextPlain = Self.mergeWithOverlap(previous: plain, next: segment.text)
            let suffix = String(nextPlain.dropFirst(min(plain.count, nextPlain.count)))
            if previous.trailingPauseSeconds >= threshold, !suffix.isEmpty {
                marked += " \(Self.pauseMarker(previous.trailingPauseSeconds)) "
                marked += suffix.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                marked += suffix
            }
            plain = nextPlain
            previous = segment
        }
        return marked
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
        let normalizedPrev = TranscriptOverlapUtilities.normalized(previous)
        let normalizedNext = TranscriptOverlapUtilities.normalized(trimmedNext)
        let nPrev = Array(normalizedPrev)
        let nNext = Array(normalizedNext)
        let normProbe = min(64, nPrev.count, nNext.count)
        if normProbe > 0 {
            for length in stride(from: normProbe, through: 2, by: -1) {
                if nPrev.suffix(length).elementsEqual(nNext.prefix(length)) {
                    // Map normalized overlap length back to raw `next` drop count.
                    let drop = TranscriptOverlapUtilities.rawDropCount(
                        in: trimmedNext,
                        normalizedPrefixLength: length
                    )
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

    private func naiveWithPauseMarks(threshold: Double) -> String {
        var pieces: [String] = []
        for (offset, segment) in segments.enumerated() {
            pieces.append(segment.text)
            if segment.trailingPauseSeconds >= threshold, offset < segments.count - 1 {
                pieces.append(Self.pauseMarker(segment.trailingPauseSeconds))
            }
        }
        return pieces.joined(separator: " ")
    }

    private static func pauseMarker(_ seconds: Double) -> String {
        "⟨\(String(format: "%.1f", seconds))s⟩"
    }
}
