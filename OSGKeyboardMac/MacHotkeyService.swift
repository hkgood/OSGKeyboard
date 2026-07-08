// MacHotkeyService.swift
// OSGKeyboard · Mac
//
// Global hold-to-talk: while Option (⌥) is held, dictation runs. Mirrors
// Typeless / SayIt push-to-talk from any foreground app.

import AppKit
import Foundation

@MainActor
final class MacHotkeyService {
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var optionHeld = false
    private var isEnabled = true

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled, optionHeld {
            optionHeld = false
            onPressEnded?()
        }
    }

    func start() {
        guard globalFlagsMonitor == nil else { return }
        _ = MacTextInsertionService.requestAccessibilityIfNeeded()

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
            return event
        }
    }

    func stop() {
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
            self.globalFlagsMonitor = nil
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
            self.localFlagsMonitor = nil
        }
        if optionHeld {
            optionHeld = false
            onPressEnded?()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isEnabled else { return }
        let optionDown = event.modifierFlags.contains(.option)
        if optionDown, !optionHeld {
            optionHeld = true
            onPressBegan?()
        } else if !optionDown, optionHeld {
            optionHeld = false
            onPressEnded?()
        }
    }
}
