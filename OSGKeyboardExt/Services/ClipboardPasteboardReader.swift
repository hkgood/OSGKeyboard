// ClipboardPasteboardReader.swift
// OSGKeyboard · Keyboard Extension
//
// Opportunity-read of UIPasteboard for clipboard-command eligibility.

import UIKit
import OSGKeyboardShared

enum ClipboardPasteboardReader {
    static func sample() -> (changeCount: Int, text: String?) {
        let board = UIPasteboard.general
        let changeCount = board.changeCount
        // Prefer plain strings; avoid forcing non-text pasteboard items.
        let text = board.hasStrings ? board.string : nil
        return (changeCount, text)
    }
}
