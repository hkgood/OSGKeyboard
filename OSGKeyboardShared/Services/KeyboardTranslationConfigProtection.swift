// KeyboardTranslationConfigProtection.swift
// OSGKeyboard · Shared
//
// Chip-side translation writes need a short grace window so the keyboard's
// 1 Hz App Group poll does not clobber the value before it lands.

import Foundation

public enum KeyboardTranslationConfigProtection {
    /// Matches the historical 2.5 s grace used by `KeyboardConfigSync`.
    public static let chipWriteGraceSeconds: TimeInterval = 2.5

    public static func shouldProtect(until: Date?, now: Date = Date()) -> Bool {
        guard let until else { return false }
        return now < until
    }

    public static func protectionDeadline(now: Date = Date()) -> Date {
        now.addingTimeInterval(chipWriteGraceSeconds)
    }
}
