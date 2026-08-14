// PeriodShortcut.swift
// OSGKeyboard · Shared
//
// iOS "." Shortcut: a second Space shortly after a Space that follows a
// word character becomes ". " and arms sentence Shift.

import Foundation

public enum PeriodShortcut: Sendable {
    /// Window for the second Space tap. Slow consecutive spaces stay spaces.
    public static let doubleTapInterval: TimeInterval = 0.45

    /// Whether `precedingText` (already including the first space) can take
    /// the shortcut: `…X ` where X is a letter or number, not a terminator.
    public static func shouldReplacePreviousSpace(precedingText: String) -> Bool {
        guard precedingText.last == " " else { return false }
        guard let previous = precedingText.dropLast().last else { return false }
        if previous.isWhitespace || previous.isNewline { return false }
        return previous.isLetter || previous.isNumber
    }

    /// After inserting a space, arm only when that space followed a word char.
    public static func shouldArm(afterSpaceFollowing precedingBeforeSpace: String) -> Bool {
        guard let last = precedingBeforeSpace.last else { return false }
        if last.isWhitespace || last.isNewline { return false }
        return last.isLetter || last.isNumber
    }
}
