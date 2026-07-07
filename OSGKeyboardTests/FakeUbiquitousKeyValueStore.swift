// FakeUbiquitousKeyValueStore.swift
// OSGKeyboardTests
//
// In-memory KVS fake for hermetic iCloud sync tests.

import Foundation
@testable import OSGKeyboardShared

final class FakeUbiquitousKeyValueStore: UbiquitousKeyValueStoreing, @unchecked Sendable {
    private var storage: [String: Any] = [:]

    func data(forKey key: String) -> Data? {
        storage[key] as? Data
    }

    func set(_ value: Data?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func object(forKey key: String) -> Any? {
        storage[key]
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func synchronize() -> Bool { true }
}
