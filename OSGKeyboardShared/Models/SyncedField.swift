// SyncedField.swift
// OSGKeyboard · Shared
//
// Per-field metadata for conflict-free settings merge across devices.

import Foundation

public struct SyncedField<T: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var value: T
    public var updatedAt: Date
    public var deviceID: String

    public init(value: T, updatedAt: Date = Date(), deviceID: String) {
        self.value = value
        self.updatedAt = updatedAt
        self.deviceID = deviceID
    }

    /// Pick the field with the newer `updatedAt`; ties break lexicographically on `deviceID`.
    public static func merge(local: SyncedField<T>, remote: SyncedField<T>) -> SyncedField<T> {
        if remote.updatedAt > local.updatedAt { return remote }
        if local.updatedAt > remote.updatedAt { return local }
        return remote.deviceID >= local.deviceID ? remote : local
    }

    public static func make(value: T, deviceID: String) -> SyncedField<T> {
        SyncedField(value: value, updatedAt: Date(), deviceID: deviceID)
    }
}
