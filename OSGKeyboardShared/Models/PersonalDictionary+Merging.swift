// PersonalDictionary+Merging.swift
// OSGKeyboard · Shared
//
// Deterministic merge rules for iCloud KVS sync. Pure logic — no
// NSUbiquitousKeyValueStore dependency so unit tests stay hermetic.

import Foundation

extension PersonalDictionary {
    public static let kvsKeyV2 = "personalDictionary.v2"
    public static let legacyKVSKey = "personalDictionary.v1"
    public static let tombstoneRetention: TimeInterval = 90 * 24 * 60 * 60

    /// Merges two dictionary snapshots for cross-device sync.
    ///
    /// Rules:
    /// - Apply `clearedAt` and deletion tombstones before entry union.
    /// - Same `id`: keep the entry with the newer `updatedAt`.
    /// - Same canonical term (case-insensitive) but different `id`: union
    ///   aliases, take max `usageCount`, keep the newer entry's fields.
    public static func merge(local: PersonalDictionary, remote: PersonalDictionary) -> PersonalDictionary {
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

        var mergedByID: [UUID: Entry] = [:]
        var canonicalOwner: [String: UUID] = [:]

        func insertOrMerge(_ candidate: Entry) {
            if deletedIDs[candidate.id] != nil { return }
            if let clearedAt, candidate.createdAt <= clearedAt { return }

            let key = candidate.term.lowercased()
            if let existingID = canonicalOwner[key], var existing = mergedByID[existingID] {
                if candidate.id == existingID {
                    mergedByID[existingID] = resolveEntryConflict(existing: existing, incoming: candidate)
                    return
                }
                existing = mergeSameTerm(existing: existing, incoming: candidate)
                mergedByID[existingID] = existing
                return
            }

            if let existing = mergedByID[candidate.id] {
                mergedByID[candidate.id] = resolveEntryConflict(existing: existing, incoming: candidate)
                canonicalOwner[key] = candidate.id
                return
            }

            mergedByID[candidate.id] = candidate
            canonicalOwner[key] = candidate.id
        }

        for entry in local.entries { insertOrMerge(entry) }
        for entry in remote.entries { insertOrMerge(entry) }

        let mergedEntries = mergedByID.values.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }

        let lastSyncedAt = [local.lastSyncedAt, remote.lastSyncedAt]
            .compactMap { $0 }
            .max()

        return PersonalDictionary(
            entries: mergedEntries,
            version: max(local.version, remote.version) + 1,
            lastSyncedAt: lastSyncedAt,
            deletedEntryIDs: deletedIDs,
            clearedAt: clearedAt
        )
    }

    public mutating func recordDeletion(of entryID: UUID, at date: Date = Date()) {
        deletedEntryIDs[entryID] = date
        entries.removeAll { $0.id == entryID }
    }

    public mutating func recordClearAll(at date: Date = Date()) {
        entries.removeAll()
        clearedAt = date
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
            if deletedAt < cutoff { return false }
            if let clearedAt, deletedAt <= clearedAt { return false }
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

    private static func resolveEntryConflict(existing: Entry, incoming: Entry) -> Entry {
        incoming.updatedAt >= existing.updatedAt ? incoming : existing
    }

    private static func mergeSameTerm(existing: Entry, incoming: Entry) -> Entry {
        let winner = incoming.updatedAt >= existing.updatedAt ? incoming : existing
        let loser = winner.id == existing.id ? incoming : existing
        var merged = winner
        merged.aliases = unionAliases(
            existing: winner.aliases,
            incoming: loser.aliases,
            excludingTerm: winner.term
        )
        merged.usageCount = max(winner.usageCount, loser.usageCount)
        merged.updatedAt = max(winner.updatedAt, loser.updatedAt)
        return merged
    }

    private static func unionAliases(
        existing: [String],
        incoming: [String],
        excludingTerm: String
    ) -> [String] {
        let termLower = excludingTerm.lowercased()
        return Array(
            Set((existing + incoming).filter { $0.lowercased() != termLower })
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
