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

    /// A remote timestamp may be at most this far in OUR future before we
    /// stop trusting it. Wall-clock LWW breaks down when one device's clock
    /// runs fast: its edits would win every merge forever, silently
    /// discarding later edits from correct-clock devices. Anything beyond
    /// this skew is a broken clock, not a newer edit.
    public static var maxTrustedFutureSkew: TimeInterval { 6 * 60 * 60 }

    /// Pick the field with the newer `updatedAt`; ties break lexicographically on `deviceID`.
    ///
    /// Broken-clock containment: comparing with clamped stamps alone is not
    /// enough — a far-future stamp stored in the winner would keep beating
    /// every later genuine edit (whose stamps are merely "now") until that
    /// wall-clock date actually arrived. So when the winner carries an
    /// untrusted future stamp, the stamp itself is REWRITTEN to "now" in the
    /// merged result: from then on any real edit, made later, outranks it.
    public static func merge(local: SyncedField<T>, remote: SyncedField<T>) -> SyncedField<T> {
        let now = Date()
        let horizon = now.addingTimeInterval(maxTrustedFutureSkew)
        let remoteAt = remote.updatedAt > horizon ? now : remote.updatedAt
        let localAt = local.updatedAt > horizon ? now : local.updatedAt
        let winner: SyncedField<T>
        if remoteAt > localAt {
            winner = remote
        } else if localAt > remoteAt {
            winner = local
        } else {
            winner = remote.deviceID >= local.deviceID ? remote : local
        }
        guard winner.updatedAt > horizon else { return winner }
        return SyncedField(value: winner.value, updatedAt: now, deviceID: winner.deviceID)
    }

    public static func make(value: T, deviceID: String) -> SyncedField<T> {
        SyncedField(value: value, updatedAt: Date(), deviceID: deviceID)
    }
}
