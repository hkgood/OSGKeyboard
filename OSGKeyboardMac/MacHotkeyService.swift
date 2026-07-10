// MacHotkeyService.swift
// OSGKeyboard · Mac
//
// Global hold-to-talk: while the configured Option (⌥) key is held, dictation
// runs. Mirrors Typeless / SayIt push-to-talk from any foreground app.

import AppKit
import Foundation

/// Which physical Option (⌥) key triggers global hold-to-talk.
///
/// Right Option is the default: the left key is a routine typing modifier
/// (special characters, app shortcuts), so firing on any Option press
/// constantly misfires during normal typing.
enum MacHotkeyTrigger: String, CaseIterable, Identifiable {
    case rightOption
    case leftOption
    case eitherOption

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .rightOption:  return "mac.hotkeyTrigger.rightOption"
        case .leftOption:   return "mac.hotkeyTrigger.leftOption"
        case .eitherOption: return "mac.hotkeyTrigger.eitherOption"
        }
    }

    /// Main-window hint under the record button — must follow the picker,
    /// or the UI tells left-Option users to hold the right key.
    var hintKey: String {
        switch self {
        case .rightOption:  return "mac.hint.hold.rightOption"
        case .leftOption:   return "mac.hint.hold.leftOption"
        case .eitherOption: return "mac.hint.hold.eitherOption"
        }
    }

    /// `@AppStorage`-compatible key; persisted via the view model's defaults.
    static let storageKey = "mac.hotkeyTrigger"

    /// Device-dependent modifier bits (IOKit `NX_DEVICELALTKEYMASK` /
    /// `NX_DEVICERALTKEYMASK`) that `.flagsChanged` events carry alongside the
    /// device-independent `.option` flag, telling left and right apart.
    private static let leftOptionMask: UInt = 0x20
    private static let rightOptionMask: UInt = 0x40

    /// Whether this trigger's key is currently down in a `.flagsChanged` event.
    func isPressed(in event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.option) else { return false }
        let raw = event.modifierFlags.rawValue
        switch self {
        case .rightOption:  return raw & Self.rightOptionMask != 0
        case .leftOption:   return raw & Self.leftOptionMask != 0
        case .eitherOption: return true
        }
    }
}

@MainActor
final class MacHotkeyService {
    /// How long the trigger key must stay held before recording begins.
    /// Filters out quick ⌥-taps and ⌥+key combos (special characters, app
    /// shortcuts) that would otherwise start and immediately abort dictation.
    private static let holdDebounce: Duration = .milliseconds(150)

    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    var trigger: MacHotkeyTrigger = .rightOption

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    /// The trigger key is physically down (debounce may still be pending).
    private var triggerKeyDown = false
    /// `onPressBegan` has fired and `onPressEnded` is owed.
    private var pressActive = false
    private var pendingBegin: Task<Void, Never>?
    private var isEnabled = true

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { cancelPress() }
    }

    func start() {
        guard globalFlagsMonitor == nil, localFlagsMonitor == nil else { return }
        // Global monitors require Accessibility; without it the call returns
        // nil and Option-hold never fires outside our own windows.
        let trusted = MacTextInsertionService.requestAccessibilityIfNeeded()

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
            return event
        }

        #if DEBUG
        if !trusted || globalFlagsMonitor == nil {
            NSLog("[OSGKeyboard] Hotkey global monitor unavailable — grant Accessibility in System Settings")
        }
        #endif
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
        cancelPress()
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isEnabled else { return }
        let triggerDown = trigger.isPressed(in: event)
        if triggerDown, !triggerKeyDown {
            triggerKeyDown = true
            scheduleBegin()
        } else if !triggerDown, triggerKeyDown {
            triggerKeyDown = false
            pendingBegin?.cancel()
            pendingBegin = nil
            if pressActive {
                pressActive = false
                onPressEnded?()
            }
        }
    }

    /// Debounce: begin only after the key has stayed held for `holdDebounce`.
    /// Releasing the key first cancels the pending start, so a quick
    /// Option+key combo never triggers recording.
    private func scheduleBegin() {
        pendingBegin?.cancel()
        pendingBegin = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDebounce)
            guard let self, !Task.isCancelled else { return }
            self.pendingBegin = nil
            guard self.isEnabled, self.triggerKeyDown, !self.pressActive else { return }
            self.pressActive = true
            self.onPressBegan?()
        }
    }

    private func cancelPress() {
        pendingBegin?.cancel()
        pendingBegin = nil
        triggerKeyDown = false
        if pressActive {
            pressActive = false
            onPressEnded?()
        }
    }
}
