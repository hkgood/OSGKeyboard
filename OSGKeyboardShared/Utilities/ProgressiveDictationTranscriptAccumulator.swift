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
                  trimmed.hasPrefix(last.text) || last.text.hasPrefix(trimmed) {
            // Cumulative progressive update without a range change.
            let longer = trimmed.count >= last.text.count ? trimmed : last.text
            segments[segments.count - 1].text = longer
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
}
