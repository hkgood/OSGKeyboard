// MacTextInsertionService.swift
// OSGKeyboard · Mac
//
// Inserts transcribed text into the target app: clipboard first, then
// a synthetic ⌘V (SayIt / Typeless-style). Requires Accessibility trust.
// Re-activates the app the user was dictating into (the popover steals
// focus) and restores the original clipboard once the paste has landed.

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

    // MARK: - Paste-target tracking

    /// Start observing app activations early (app launch) so a paste target
    /// can still be recovered while OSGKeyboard itself is frontmost — e.g.
    /// when a recording is started from the menu-bar popover.
    @MainActor
    static func beginTrackingFrontmostApp() {
        _ = FrontmostAppTracker.shared
    }

    /// The app a synthesized ⌘V should land in: the current frontmost app,
    /// or — when OSGKeyboard is frontmost because the popover has key
    /// focus — the app that was active immediately before it.
    @MainActor
    static func captureTargetApplication() -> NSRunningApplication? {
        let selfPid = NSRunningApplication.current.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != selfPid {
            return front
        }
        return FrontmostAppTracker.shared.lastExternalApp
    }

    // MARK: - Insertion

    /// Copy to pasteboard and optionally simulate ⌘V in the target app.
    /// Returns `true` only if the ⌘V event was actually synthesized. After a
    /// successful paste the user's original clipboard is put back, so
    /// dictation never permanently clobbers it.
    @MainActor
    static func insert(
        _ text: String,
        autoPaste: Bool,
        targetApp: NSRunningApplication? = nil
    ) async throws -> Bool {
        guard !text.isEmpty else { return false }
        let pasteboard = NSPasteboard.general
        let snapshot = snapshotItems(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard autoPaste else { return false }
        guard AXIsProcessTrusted() else { throw InsertionError.accessibilityNotGranted }

        // Make sure ⌘V lands in the app the user was dictating into, not in
        // OSGKeyboard's own popover / window.
        if let targetApp { await activate(targetApp) }
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard postCommandV() else { return false }

        // Give the target app time to read the transcript off the
        // pasteboard, then restore whatever the user had on it.
        try? await Task.sleep(nanoseconds: 300_000_000)
        restoreItems(snapshot, to: pasteboard)
        return true
    }

    /// Brings `app` forward and waits (up to ~1 s) until it is frontmost so
    /// the synthesized keystroke isn't swallowed mid-switch.
    @MainActor
    private static func activate(_ app: NSRunningApplication) async {
        func isFront() -> Bool {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        }
        guard !isFront() else { return }
        app.activate()
        var attempts = 0
        while !isFront(), attempts < 20 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            attempts += 1
        }
    }

    // MARK: - Pasteboard preservation

    /// Every representation of every pasteboard item, so restore round-trips
    /// rich content (images, files, multiple flavours) losslessly.
    private static func snapshotItems(
        of pasteboard: NSPasteboard
    ) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { flavours, type in
                flavours[type] = item.data(forType: type)
            }
        }
    }

    private static func restoreItems(
        _ items: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard
    ) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { flavours in
            let item = NSPasteboardItem()
            for (type, data) in flavours { item.setData(data, forType: type) }
            return item
        })
    }

    /// Returns `false` when the CGEvents could not be created — in that case
    /// nothing was pasted and callers must not report success.
    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
        return true
    }
}

// MARK: - Frontmost-app tracker

/// Remembers the most recent non-OSGKeyboard frontmost app. Needed because
/// the menu-bar popover activates OSGKeyboard, hiding the real paste target
/// from `NSWorkspace.frontmostApplication`.
@MainActor
private final class FrontmostAppTracker: NSObject {
    static let shared = FrontmostAppTracker()

    private(set) var lastExternalApp: NSRunningApplication?

    private override init() {
        super.init()
        // Seed with whatever is frontmost now (usually not us at launch).
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != NSRunningApplication.current.processIdentifier {
            lastExternalApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            app.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return }
        lastExternalApp = app
    }
}
