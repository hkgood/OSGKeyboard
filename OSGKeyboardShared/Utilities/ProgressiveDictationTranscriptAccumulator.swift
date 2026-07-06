// ProgressiveDictationTranscriptAccumulator.swift
// OSGKeyboard · Shared
//
// Merges progressive `DictationTranscriber` results into one transcript.
// Short-form presets may emit a new time range after ~30 s; treating the
// latest partial as the full transcript drops earlier segments.

import Foundation
import CoreMedia

/// Combines volatile partials and finalized segments from
/// `DictationTranscriber.results` into a single growing transcript.
public struct ProgressiveDictationTranscriptAccumulator: Sendable {

    private struct Segment: Sendable {
        let startSeconds: Double
        var text: String
    }

    private var segments: [Segment] = []
    private var lastEmitted = ""

    public init() {}

    /// Ingest one analyzer result. Returns a non-nil full transcript when the
    /// composed text changed since the previous emission.
    public mutating func ingest(range: CMTimeRange, text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let start = range.start.seconds

        if let idx = segments.lastIndex(where: { abs($0.startSeconds - start) < 0.001 }) {
            // Same audio window — volatile refinement of the current segment.
            segments[idx].text = trimmed
        } else if let last = segments.last,
                  let revision = Self.revisionText(
                    previous: last.text,
                    candidate: trimmed,
                    startDelta: abs(last.startSeconds - start)
                  ) {
            // Cumulative progressive update with a small range drift. SpeechAnalyzer
            // may add punctuation while nudging the range start; treat that as a
            // refinement, not a new sentence.
            segments[segments.count - 1].text = revision
        } else {
            // New time range — append instead of replacing earlier speech.
            segments.append(Segment(startSeconds: start, text: trimmed))
        }

        let full = composedText()
        guard full != lastEmitted else { return nil }
        lastEmitted = full
        return full
    }

    /// Final composed transcript after the results stream finishes.
    public mutating func finalize() -> String {
        let full = composedText()
        lastEmitted = full
        return full
    }

    private func composedText() -> String {
        segments.reduce(into: "") { partial, segment in
            partial = DictationTextComposer.compose(anchor: partial, live: segment.text)
        }
    }

    private static func revisionText(
        previous: String,
        candidate: String,
        startDelta: Double
    ) -> String? {
        let normalizedPrevious = DictationTextComposer.normalizeForOverlap(previous)
        let normalizedCandidate = DictationTextComposer.normalizeForOverlap(candidate)
        guard !normalizedPrevious.isEmpty, !normalizedCandidate.isEmpty else {
            return nil
        }

        if candidate.hasPrefix(previous) || previous.hasPrefix(candidate) {
            return candidate.count >= previous.count ? candidate : previous
        }

        // Avoid collapsing genuinely separate long ranges; this only handles
        // volatile corrections whose time range start drifted slightly.
        guard startDelta <= 1.0 else { return nil }

        if normalizedCandidate.hasPrefix(normalizedPrevious)
            || normalizedPrevious.hasPrefix(normalizedCandidate)
            || normalizedCandidate.contains(normalizedPrevious)
            || normalizedPrevious.contains(normalizedCandidate) {
            return normalizedCandidate.count >= normalizedPrevious.count ? candidate : previous
        }

        let overlap = longestNormalizedOverlap(
            previous: normalizedPrevious,
            candidate: normalizedCandidate
        )
        let shorter = min(normalizedPrevious.count, normalizedCandidate.count)
        guard shorter >= 4, Double(overlap) / Double(shorter) >= 0.8 else {
            return nil
        }
        return normalizedCandidate.count >= normalizedPrevious.count ? candidate : previous
    }

    private static func longestNormalizedOverlap(previous: String, candidate: String) -> Int {
        let previousChars = Array(previous)
        let candidateChars = Array(candidate)
        let maxProbe = min(64, previousChars.count, candidateChars.count)
        guard maxProbe > 0 else { return 0 }
        for length in stride(from: maxProbe, through: 1, by: -1) {
            if previousChars.suffix(length).elementsEqual(candidateChars.prefix(length)) {
                return length
            }
        }
        return 0
    }
}
