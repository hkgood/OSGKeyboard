// TypingAutocapitalization.swift
// OSGKeyboard · Shared
//
// Decides when the English letter page should arm Shift once for
// automatic capitalization (mirrors UITextAutocapitalizationType).

import Foundation

public enum TypingAutocapitalizationMode: String, Sendable, Equatable {
    case none
    case words
    case sentences
    case allCharacters
}

public enum TypingAutocapitalization: Sendable {
    /// Whether Shift should be armed for the next Latin letter.
    public static func shouldCapitalize(
        precedingText: String?,
        mode: TypingAutocapitalizationMode
    ) -> Bool {
        switch mode {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return needsWordCapitalization(precedingText)
        case .sentences:
            return needsSentenceCapitalization(precedingText)
        }
    }

    // MARK: - Private

    private static func needsWordCapitalization(_ preceding: String?) -> Bool {
        guard let preceding, !preceding.isEmpty else { return true }
        guard let last = preceding.last else { return true }
        return last.isWhitespace || last.isNewline
    }

    private static func needsSentenceCapitalization(_ preceding: String?) -> Bool {
        guard let preceding, !preceding.isEmpty else { return true }

        // Walk backward from the caret. Trailing spaces are ignored; a newline
        // itself starts a new line (system .sentences behavior, e.g. Notes
        // after Return). Otherwise capitalize only after a sentence terminator.
        var index = preceding.endIndex
        while index > preceding.startIndex {
            index = preceding.index(before: index)
            let character = preceding[index]
            if character.isNewline {
                return true
            }
            if character.isWhitespace {
                continue
            }
            return isSentenceTerminator(character)
        }
        return true
    }

    private static func isSentenceTerminator(_ character: Character) -> Bool {
        switch character {
        case ".", "!", "?", "…", "。", "！", "？":
            return true
        default:
            return false
        }
    }
}
