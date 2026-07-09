// SyncedSpeechHistory.swift
// OSGKeyboard · Shared
//
// iCloud KVS payload for speech history. Tombstones and `clearedAt`
// propagate single-entry deletes and "clear all" across devices.

import Foundation

public struct SyncedSpeechHistory: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let kvsKey = "speechHistory.v2"
    public static let legacyKVSKey = "speechHistory.v1"
    public static let maxEntries = 300
    /// Tombstones older than this window may be pruned during merge.
    public static let tombstoneRetention: TimeInterval = 90 * 24 * 60 * 60

    public var schemaVersion: Int
    public var updatedAt: Date
    public var entries: [SpeechHistoryEntry]
    /// Entry IDs deleted on any device, with deletion timestamps.
    public var deletedEntryIDs: [UUID: Date]
    /// When set, entries created at or before this instant are excluded.
    public var clearedAt: Date?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        updatedAt: Date = Date(),
        entries: [SpeechHistoryEntry] = [],
        deletedEntryIDs: [UUID: Date] = [:],
        clearedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.entries = entries
        self.deletedEntryIDs = deletedEntryIDs
        self.clearedAt = clearedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        entries = try container.decodeIfPresent([SpeechHistoryEntry].self, forKey: .entries) ?? []
        if let map = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedEntryIDs) {
            deletedEntryIDs = map
        } else if let legacyIDs = try container.decodeIfPresent([UUID].self, forKey: .deletedEntryIDs) {
            let stamp = Date()
            deletedEntryIDs = Dictionary(uniqueKeysWithValues: legacyIDs.map { ($0, stamp) })
        } else {
            deletedEntryIDs = [:]
        }
        clearedAt = try container.decodeIfPresent(Date.self, forKey: .clearedAt)
    }

    public static let empty = SyncedSpeechHistory(updatedAt: .distantPast)

    /// Union entries by id (newer `createdAt` wins), apply tombstones and clear.
    public static func merge(local: SyncedSpeechHistory, remote: SyncedSpeechHistory) -> SyncedSpeechHistory {
        let clearedAt = later(of: local.clearedAt, and: remote.clearedAt)
        var deletedIDs = local.deletedEntryIDs
        for (id, date) in remote.deletedEntryIDs {
            if let existing = deletedIDs[id] {
                deletedIDs[id] = max(existing, date)
            } else {
                deletedIDs[id] = date
            }
        }
        deletedIDs = pruneTombstones(deletedIDs, clearedAt: clearedAt)

        var byID: [UUID: SpeechHistoryEntry] = [:]
        for entry in local.entries + remote.entries {
            if deletedIDs[entry.id] != nil { continue }
            if let clearedAt, entry.createdAt <= clearedAt { continue }
            if let existing = byID[entry.id] {
                byID[entry.id] = entry.createdAt >= existing.createdAt ? entry : existing
            } else {
                byID[entry.id] = entry
            }
        }

        var entries = Array(byID.values).sorted { $0.createdAt > $1.createdAt }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        return SyncedSpeechHistory(
            updatedAt: max(local.updatedAt, remote.updatedAt),
            entries: entries,
            deletedEntryIDs: deletedIDs,
            clearedAt: clearedAt
        )
    }

    /// Trim to the newest `maxEntries` rows (call after local-only appends).
    public mutating func trimEntries() {
        guard entries.count > Self.maxEntries else { return }
        entries = Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maxEntries))
        updatedAt = Date()
    }

    public mutating func pruneTombstonesIfNeeded() {
        deletedEntryIDs = Self.pruneTombstones(deletedEntryIDs, clearedAt: clearedAt)
    }

    private static func pruneTombstones(
        _ tombstones: [UUID: Date],
        clearedAt: Date?
    ) -> [UUID: Date] {
        let cutoff = Date().addingTimeInterval(-tombstoneRetention)
        return tombstones.filter { _, deletedAt in
            if deletedAt < cutoff {
                return false
            }
            if let clearedAt, deletedAt <= clearedAt {
                return false
            }
            return true
        }
    }

    private static func later(of lhs: Date?, and rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return max(left, right)
        case (nil, let right?):
            return right
        case (let left?, nil):
            return left
        case (nil, nil):
            return nil
        }
    }
}

extension SyncedSpeechHistory {
    mutating func recordClearAll(at date: Date = Date()) {
        entries.removeAll()
        clearedAt = date
    }
}
