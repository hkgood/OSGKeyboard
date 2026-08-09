// ClipboardCommandResume.swift
// OSGKeyboard · Shared
//
// One persisted intent so the system「允许粘贴」alert can dismiss / recreate
// the keyboard extension without losing acquisition / warm-up / recording state.

import Foundation

public struct ClipboardCommandIntent: Codable, Equatable, Sendable {
    public enum Stage: String, Codable, Sendable {
        case acquiringPaste
        case waitingForHost
        case startIssued
    }

    public let id: UUID
    public var stage: Stage
    public var snapshot: String?
    public var updatedAt: TimeInterval

    public init(
        id: UUID = UUID(),
        stage: Stage = .acquiringPaste,
        snapshot: String? = nil,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.stage = stage
        self.snapshot = snapshot
        self.updatedAt = updatedAt
    }
}

public enum ClipboardCommandResume: Sendable {
    private enum Key {
        static let intent = "clipboardCommand.intent.v2"
        // Removed v1 keys. Keep names only so an upgrade clears stale partial state.
        static let legacyPreferVoice = "clipboardCommand.preferVoice.v1"
        static let legacySnapshot = "clipboardCommand.pendingSnapshot.v1"
        static let legacyMarkedAt = "clipboardCommand.preferVoiceAt.v1"
        static let legacyStartIssuedUtterance = "clipboardCommand.startIssuedUtterance.v1"
    }

    /// How long a sticky prefer-voice / snapshot remains valid.
    public static let stickyTTL: TimeInterval = 120
    /// Max time to wait in「准备录音…」for host confirm before failing closed.
    public static let preparingTimeout: TimeInterval = 6

    @discardableResult
    public static func beginIntent(defaults: UserDefaults? = nil) -> ClipboardCommandIntent? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return nil }
        let intent = ClipboardCommandIntent()
        write(intent, store: store)
        return intent
    }

    /// Compatibility entry point for surface-selection callers and older tests.
    public static func markPreferVoice(defaults: UserDefaults? = nil) {
        guard currentIntent(defaults: defaults) == nil else { return }
        _ = beginIntent(defaults: defaults)
    }

    public static func storeSnapshot(_ text: String, defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var intent = currentIntent(defaults: store) ?? ClipboardCommandIntent()
        intent.snapshot = trimmed
        intent.stage = .waitingForHost
        intent.updatedAt = Date().timeIntervalSince1970
        write(intent, store: store)
    }

    public static func markStartIssued(_ utteranceId: UUID, defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        let existing = currentIntent(defaults: store)
        var intent = ClipboardCommandIntent(
            id: utteranceId,
            stage: .startIssued,
            snapshot: existing?.snapshot
        )
        intent.updatedAt = Date().timeIntervalSince1970
        write(intent, store: store)
    }

    public static func startIssuedUtteranceId(defaults: UserDefaults? = nil) -> UUID? {
        guard let intent = currentIntent(defaults: defaults),
              intent.stage == .startIssued else { return nil }
        return intent.id
    }

    public static func hasStartIssued(defaults: UserDefaults? = nil) -> Bool {
        startIssuedUtteranceId(defaults: defaults) != nil
    }

    public static func clear(defaults: UserDefaults? = nil) {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return }
        store.removeObject(forKey: Key.intent)
        clearLegacy(store: store)
        store.synchronize()
    }

    public static func shouldPreferVoice(defaults: UserDefaults? = nil) -> Bool {
        currentIntent(defaults: defaults) != nil
    }

    public static func pendingSnapshot(defaults: UserDefaults? = nil) -> String? {
        currentIntent(defaults: defaults)?.snapshot
    }

    public static func currentIntent(
        defaults: UserDefaults? = nil
    ) -> ClipboardCommandIntent? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return nil }
        guard let data = store.data(forKey: Key.intent),
              let intent = try? JSONDecoder().decode(ClipboardCommandIntent.self, from: data) else {
            clearLegacy(store: store)
            return nil
        }
        if Date().timeIntervalSince1970 - intent.updatedAt > stickyTTL {
            clear(defaults: store)
            return nil
        }
        return intent
    }

    private static func write(_ intent: ClipboardCommandIntent, store: UserDefaults) {
        guard let data = try? JSONEncoder().encode(intent) else { return }
        store.set(data, forKey: Key.intent)
        clearLegacy(store: store)
        // Paste alerts may suspend or jetsam the extension immediately.
        store.synchronize()
    }

    private static func clearLegacy(store: UserDefaults) {
        let keys = [
            Key.legacyPreferVoice,
            Key.legacySnapshot,
            Key.legacyMarkedAt,
            Key.legacyStartIssuedUtterance
        ]
        if keys.contains(where: { store.object(forKey: $0) != nil }) {
            keys.forEach { store.removeObject(forKey: $0) }
            store.synchronize()
        }
    }
}
