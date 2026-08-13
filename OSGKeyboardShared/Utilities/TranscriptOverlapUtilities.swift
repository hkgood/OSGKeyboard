// TranscriptOverlapUtilities.swift
// OSGKeyboard · Shared
//
// Shared normalization and raw-prefix mapping for transcript overlap checks.

import Foundation

enum TranscriptOverlapUtilities {
    static func normalized(_ text: String) -> String {
        text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }.map { Character($0) }.reduce(into: "") { $0.append($1) }
    }

    static func rawDropCount(in text: String, normalizedPrefixLength: Int) -> Int {
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
}
