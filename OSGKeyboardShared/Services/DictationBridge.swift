// DictationBridge.swift
// OSGKeyboard · Shared
//
// Lightweight App Group bridge for host-app dictation handoff:
//   keyboard extension -> open host app for recording
//   host app           -> writes final transcript
//   keyboard extension -> consumes pending transcript and inserts text
//
// STATUS (v0.1.2): Retained. Consumed by `KeyboardViewController` for
// the "one-shot" host-app dictation path (where the keyboard extension
// launches the host app, the user records there, and the resulting
// text is consumed back by the extension). The *continuous* path goes
// through `FlowSessionBridge` + `FlowSessionManager` instead.

import Foundation

public enum DictationBridge {
    public enum Status: String, Sendable, Equatable {
        case idle
        case requested
        case recording
        case transcribing
        case done
        case cancelled
        case error
    }

    private enum Key {
        static let pendingText = "dictation.pendingText"
        static let updatedAt = "dictation.updatedAt"
        static let status = "dictation.status"
        static let statusUpdatedAt = "dictation.statusUpdatedAt"
        static let statusMessage = "dictation.statusMessage"
    }

    private static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults {
            return defaults
        }
        return AppGroup.isAvailable ? AppGroup.defaults : .standard
    }

    public static func setStatus(
        _ status: Status,
        message: String? = nil,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        store.set(status.rawValue, forKey: Key.status)
        store.set(Date().timeIntervalSince1970, forKey: Key.statusUpdatedAt)
        if let message, !message.isEmpty {
            store.set(message, forKey: Key.statusMessage)
        } else {
            store.removeObject(forKey: Key.statusMessage)
        }
    }

    public static func currentStatus(
        defaults: UserDefaults? = nil
    ) -> (status: Status, message: String?, updatedAt: TimeInterval) {
        let store = resolvedDefaults(defaults)
        let raw = store.string(forKey: Key.status) ?? Status.idle.rawValue
        let status = Status(rawValue: raw) ?? .idle
        let message = store.string(forKey: Key.statusMessage)
        let updatedAt = store.double(forKey: Key.statusUpdatedAt)
        return (status, message, updatedAt)
    }

    public static func markRequested(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.removeObject(forKey: Key.pendingText)
        setStatus(.requested, defaults: store)
    }

    /// Store a transcript for the keyboard extension to consume.
    public static func storePendingTranscript(_ text: String, defaults: UserDefaults? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let store = resolvedDefaults(defaults)
        store.set(trimmed, forKey: Key.pendingText)
        store.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        setStatus(.done, defaults: store)
    }

    /// Returns and clears the pending transcript if present.
    public static func consumePendingTranscript(
        maxAge: TimeInterval = 180,
        defaults: UserDefaults? = nil
    ) -> String? {
        let store = resolvedDefaults(defaults)
        guard let text = store.string(forKey: Key.pendingText) else {
            return nil
        }
        if maxAge > 0 {
            let ts = store.double(forKey: Key.updatedAt)
            if ts > 0, Date().timeIntervalSince1970 - ts > maxAge {
                clear(defaults: store)
                return nil
            }
        }
        store.removeObject(forKey: Key.pendingText)
        setStatus(.idle, defaults: store)
        return text
    }

    public static func clear(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.removeObject(forKey: Key.pendingText)
        store.removeObject(forKey: Key.updatedAt)
        setStatus(.idle, defaults: store)
    }
}
