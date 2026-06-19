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
        if anchor.last == " " || anchor.last == "\n" { return anchor + trimmed }
        return anchor + " " + trimmed
    }
}
