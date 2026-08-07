// ClipboardPasteboardReader.swift
// OSGKeyboard · Keyboard Extension
//
// Pasteboard peeks for clipboard-command UI and long-press snapshot capture.
//
// Idle affordance must use metadata only (`hasStrings` / `changeCount`) so the
// system「允许粘贴」alert never appears while the keyboard is merely open.
// Content reads (`string`) happen only on an explicit long-press.

import UIKit
import OSGKeyboardShared

enum ClipboardPasteboardReader {
    /// Metadata-only — does not trigger the paste permission prompt.
    static func changeCount() -> Int {
        UIPasteboard.general.changeCount
    }

    /// Metadata-only — whether the pasteboard currently holds string items.
    static func hasStrings() -> Bool {
        UIPasteboard.general.hasStrings
    }

    /// Content sample for long-press snapshot. May present the system paste alert.
    static func sample() -> (changeCount: Int, text: String?) {
        let board = UIPasteboard.general
        let changeCount = board.changeCount
        // Prefer plain strings; avoid forcing non-text pasteboard items.
        let text = board.hasStrings ? board.string : nil
        return (changeCount, text)
    }
}
