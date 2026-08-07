// ClipboardCommandResume.swift
// OSGKeyboard · Shared
//
// Sticky App Group flags so the system「允许粘贴」alert can dismiss / recreate
// the keyboard extension without losing "stay on voice + clipboard chrome".

import Foundation

public enum ClipboardCommandResume: Sendable {
    private enum Key {
        /// Prefer voice surface on the next keyboard presentation.
        static let preferVoice = "clipboardCommand.preferVoice.v1"
        /// Frozen snapshot captured before / during paste alert (optional).
        static let snapshot = "clipboardCommand.pendingSnapshot.v1"
        /// Wall time when prefer-voice was marked (drop stale flags).
        static let markedAt = "clipboardCommand.preferVoiceAt.v1"
        /// Utterance id already sent as startRecording — blocks duplicate starts.
        static let startIssuedUtterance = "clipboardCommand.startIssuedUtterance.v1"
    }

    /// How long a sticky prefer-voice / snapshot remains valid.
    public static let stickyTTL: TimeInterval = 120
    /// Max time to wait in「准备录音…」for host confirm before failing closed.
    public static let preparingTimeout: TimeInterval = 6

    public static func markPreferVoice(defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        store.set(true, forKey: Key.preferVoice)
        store.set(Date().timeIntervalSince1970, forKey: Key.markedAt)
        // Paste alert often jetsams the extension — flush before we block on
        // UIPasteboard.string so a recreated process still sees prefer-voice.
        store.synchronize()
    }

    public static func storeSnapshot(_ text: String, defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.set(trimmed, forKey: Key.snapshot)
        store.set(true, forKey: Key.preferVoice)
        store.set(Date().timeIntervalSince1970, forKey: Key.markedAt)
        store.synchronize()
    }

    public static func markStartIssued(_ utteranceId: UUID, defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        store.set(utteranceId.uuidString, forKey: Key.startIssuedUtterance)
        store.set(true, forKey: Key.preferVoice)
        store.set(Date().timeIntervalSince1970, forKey: Key.markedAt)
        store.synchronize()
    }

    public static func startIssuedUtteranceId(defaults: UserDefaults? = nil) -> UUID? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return nil }
        pruneIfStale(store: store)
        guard let raw = store.string(forKey: Key.startIssuedUtterance) else { return nil }
        return UUID(uuidString: raw)
    }

    public static func hasStartIssued(defaults: UserDefaults? = nil) -> Bool {
        startIssuedUtteranceId(defaults: defaults) != nil
    }

    public static func clear(defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        store.removeObject(forKey: Key.preferVoice)
        store.removeObject(forKey: Key.snapshot)
        store.removeObject(forKey: Key.markedAt)
        store.removeObject(forKey: Key.startIssuedUtterance)
        store.synchronize()
    }

    public static func shouldPreferVoice(defaults: UserDefaults? = nil) -> Bool {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return false }
        pruneIfStale(store: store)
        return store.bool(forKey: Key.preferVoice)
    }

    public static func pendingSnapshot(defaults: UserDefaults? = nil) -> String? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return nil }
        pruneIfStale(store: store)
        guard store.bool(forKey: Key.preferVoice) else { return nil }
        return store.string(forKey: Key.snapshot)
    }

    private static func pruneIfStale(store: UserDefaults) {
        let markedAt = store.double(forKey: Key.markedAt)
        guard markedAt > 0 else {
            // Legacy / incomplete write — drop.
            if store.object(forKey: Key.preferVoice) != nil
                || store.object(forKey: Key.startIssuedUtterance) != nil {
                store.removeObject(forKey: Key.preferVoice)
                store.removeObject(forKey: Key.snapshot)
                store.removeObject(forKey: Key.startIssuedUtterance)
                store.synchronize()
            }
            return
        }
        if Date().timeIntervalSince1970 - markedAt > stickyTTL {
            store.removeObject(forKey: Key.preferVoice)
            store.removeObject(forKey: Key.snapshot)
            store.removeObject(forKey: Key.markedAt)
            store.removeObject(forKey: Key.startIssuedUtterance)
            store.synchronize()
        }
    }
}
