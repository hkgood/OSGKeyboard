// FlowSessionBridge.swift
// OSGKeyboard · Shared
//
// TypeWhisper-style Flow session bridge: keyboard writes recording
// signals; host app writes transcription results.

import Foundation

enum FlowSessionBridgeStorage {
    static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults { return defaults }
        guard let available = AppGroup.defaultsIfAvailable else {
            #if DEBUG
            fatalError("App Group unavailable — inject UserDefaults in tests or fix entitlements.")
            #else
            fatalError("App Group unavailable.")
            #endif
        }
        return available
    }

    /// Force cross-process visibility. Must only be called on the main thread.
    static func flush(_ store: UserDefaults) {
        if Thread.isMainThread {
            store.synchronize()
        }
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// Cross-process Flow mailbox backed by App Group defaults and lossy Darwin
/// wakeups. Payload writes precede posts, and main-thread writes synchronize
/// for visibility. Readers still poll/reload because wakeups may be missed;
/// `hostGeneration` rejects state left by a dead host process.
public enum FlowSessionBridge {
    /// Keyboard/read side: refresh App Group defaults after the extension was
    /// suspended so decisions are not based on stale in-process caches.
    public static func reloadFromDisk(defaults: UserDefaults? = nil) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if Thread.isMainThread {
            store.synchronize()
        }
    }
}
