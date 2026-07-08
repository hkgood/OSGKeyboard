// MacTextInsertionService.swift
// OSGKeyboard · Mac
//
// Inserts transcribed text into the frontmost app: clipboard first, then
// a synthetic ⌘V (SayIt / Typeless-style). Requires Accessibility trust.

import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation

enum MacTextInsertionService {
    enum InsertionError: Error, LocalizedError {
        case accessibilityNotGranted

        var errorDescription: String? {
            MacL10n.string("mac.error.accessibilityRequired")
        }
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Copy to pasteboard and optionally simulate ⌘V in the front app.
    static func insert(
        _ text: String,
        autoPaste: Bool
    ) throws -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard autoPaste else { return false }
        guard AXIsProcessTrusted() else { throw InsertionError.accessibilityNotGranted }

        Thread.sleep(forTimeInterval: 0.08)
        postCommandV()
        return true
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = CGEventFlags.maskCommand
        keyUp?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
