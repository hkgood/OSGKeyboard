// SyncedSpeechHistory.swift
// OSGKeyboard · Shared
//
// iCloud KVS payload for speech history. Tombstones and `clearedAt`
// propagate single-entry deletes and "clear all" across devices.

import CryptoKit
import Foundation

public struct SyncedSpeechHistory: Codable, Equatable, Sendable {
    public static let schemaVersion = 5
    public static let kvsKey = "speechHistory.v2"
    public static let legacyKVSKey = "speechHistory.v1"
    public static let maxEntries = 300
    /// Tombstones older than this window may be pruned during merge.
    /// Tombstones guard against deleted entries "resurrecting" when a
    /// long-offline device rejoins and re-merges them. A short wall-clock
    /// retention re-opened that window after only 90 days; a year keeps the
    /// window closed for any realistically dormant device while staying tiny
    /// on the wire (a tombstone is ~60 bytes of JSON), and the count cap
    /// bounds the worst case regardless of clock.
    public static let tombstoneRetention: TimeInterval = 365 * 24 * 60 * 60
    /// Hard cap independent of wall clock — the oldest tombstones are
    /// dropped first once exceeded.
    public static let maxTombstones = 500

    public var schemaVersion: Int
    public var updatedAt: Date
    public var entries: [SpeechHistoryEntry]
    /// Deduplicated historical style prompts keyed by SHA-256. Keeping prompt
    /// snapshots outside rows avoids multiplying a 6,000-character prompt by
    /// every dictation while still preserving the prompt used at that moment.
    public var polishStylePromptSnapshots: [String: String]
    /// Entry IDs deleted on any device, with deletion timestamps.
    public var deletedEntryIDs: [UUID: Date]
    /// Recent idempotency keys for keyboard-originated history mutations.
    public var appliedMutationIDs: [UUID]
    /// When set, entries created at or before this instant are excluded.
    public var clearedAt: Date?
    public static let maxPolishStylePromptSnapshots = 32
    public static let maxPolishStylePromptSnapshotCharacters = 96_000

    public init(
        schemaVersion: Int = Self.schemaVersion,
        updatedAt: Date = Date(),
        entries: [SpeechHistoryEntry] = [],
        polishStylePromptSnapshots: [String: String] = [:],
        deletedEntryIDs: [UUID: Date] = [:],
        appliedMutationIDs: [UUID] = [],
        clearedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.entries = entries
        self.polishStylePromptSnapshots = polishStylePromptSnapshots
        self.deletedEntryIDs = deletedEntryIDs
        self.appliedMutationIDs = appliedMutationIDs
        self.clearedAt = clearedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        entries = try container.decodeIfPresent([SpeechHistoryEntry].self, forKey: .entries) ?? []
        polishStylePromptSnapshots = try container.decodeIfPresent(
            [String: String].self,
            forKey: .polishStylePromptSnapshots
        ) ?? [:]
        if let map = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedEntryIDs) {
            deletedEntryIDs = map
        } else if let legacyIDs = try container.decodeIfPresent([UUID].self, forKey: .deletedEntryIDs) {
            let stamp = Date()
            deletedEntryIDs = Dictionary(uniqueKeysWithValues: legacyIDs.map { ($0, stamp) })
        } else {
            deletedEntryIDs = [:]
        }
        appliedMutationIDs = try container.decodeIfPresent(
            [UUID].self,
            forKey: .appliedMutationIDs
        ) ?? []
        clearedAt = try container.decodeIfPresent(Date.self, forKey: .clearedAt)
    }

    public static let empty = SyncedSpeechHistory(updatedAt: .distantPast)

    /// Union entries by id. Higher revision wins; timestamps break legacy ties.
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
        let appliedMutationIDs = Array(
            Set(local.appliedMutationIDs + remote.appliedMutationIDs)
                .sorted { $0.uuidString < $1.uuidString }
                .prefix(256)
        )

        var byID: [UUID: SpeechHistoryEntry] = [:]
        for entry in local.entries + remote.entries {
            if deletedIDs[entry.id] != nil { continue }
            if let clearedAt, entry.createdAt <= clearedAt { continue }
            if let existing = byID[entry.id] {
                byID[entry.id] = preferred(entry, over: existing)
            } else {
                byID[entry.id] = entry
            }
        }

        var entries = Array(byID.values).sorted { $0.createdAt > $1.createdAt }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }

        var snapshots = local.polishStylePromptSnapshots
        for (fingerprint, prompt) in remote.polishStylePromptSnapshots {
            snapshots[fingerprint] = snapshots[fingerprint] ?? prompt
        }

        var merged = SyncedSpeechHistory(
            updatedAt: max(local.updatedAt, remote.updatedAt),
            entries: entries,
            polishStylePromptSnapshots: snapshots,
            deletedEntryIDs: deletedIDs,
            appliedMutationIDs: appliedMutationIDs,
            clearedAt: clearedAt
        )
        merged.prunePolishStylePromptSnapshots()
        return merged
    }

    /// Trim to the newest `maxEntries` rows (call after local-only appends).
    public mutating func trimEntries() {
        if entries.count > Self.maxEntries {
            entries = Array(entries.sorted { $0.createdAt > $1.createdAt }.prefix(Self.maxEntries))
            updatedAt = Date()
        }
        prunePolishStylePromptSnapshots()
    }

    public mutating func pruneTombstonesIfNeeded() {
        deletedEntryIDs = Self.pruneTombstones(deletedEntryIDs, clearedAt: clearedAt)
    }

    private static func pruneTombstones(
        _ tombstones: [UUID: Date],
        clearedAt: Date?
    ) -> [UUID: Date] {
        let cutoff = Date().addingTimeInterval(-tombstoneRetention)
        var kept = tombstones.filter { _, deletedAt in
            if deletedAt < cutoff { return false }
            if let clearedAt, deletedAt <= clearedAt { return false }
            return true
        }
        // Enforce the count cap that makes the 365-day retention safe on the
        // KVS byte budget: keep the NEWEST tombstones (dropping an old one
        // early only re-opens the resurrection window for that one entry).
        if kept.count > maxTombstones {
            let newest = kept.sorted { $0.value > $1.value }.prefix(maxTombstones)
            kept = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        return kept
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

    private static func preferred(
        _ candidate: SpeechHistoryEntry,
        over existing: SpeechHistoryEntry
    ) -> SpeechHistoryEntry {
        let winner: SpeechHistoryEntry
        let fallback: SpeechHistoryEntry
        if candidate.revision != existing.revision {
            (winner, fallback) = candidate.revision > existing.revision
                ? (candidate, existing)
                : (existing, candidate)
        } else if candidate.modifiedAt != existing.modifiedAt {
            (winner, fallback) = candidate.modifiedAt > existing.modifiedAt
                ? (candidate, existing)
                : (existing, candidate)
        } else {
            (winner, fallback) = candidate.createdAt >= existing.createdAt
                ? (candidate, existing)
                : (existing, candidate)
        }
        return preservingCorpusMetadata(of: winner, fallback: fallback)
    }

    /// Older app versions decode and re-encode history without the v4/v5 corpus
    /// fields. A newer visible-text revision must win without erasing the only
    /// retained pre-polish sample.
    private static func preservingCorpusMetadata(
        of winner: SpeechHistoryEntry,
        fallback: SpeechHistoryEntry
    ) -> SpeechHistoryEntry {
        let usesFallbackTranscript = winner.prePolishText == nil
            && fallback.prePolishText != nil
        let prePolishText = winner.prePolishText ?? fallback.prePolishText
        let polishStyleID = winner.polishStyleID ?? fallback.polishStyleID
        let polishStylePromptFingerprint = winner.polishStylePromptFingerprint
            ?? fallback.polishStylePromptFingerprint
        guard prePolishText != winner.prePolishText
                || polishStyleID != winner.polishStyleID
                || polishStylePromptFingerprint
                    != winner.polishStylePromptFingerprint else {
            return winner
        }
        return SpeechHistoryEntry(
            id: winner.id,
            text: winner.text,
            prePolishText: prePolishText,
            wasTranslation: usesFallbackTranscript
                ? fallback.wasTranslation
                : winner.wasTranslation,
            polishStyleID: polishStyleID,
            polishStylePromptFingerprint: polishStylePromptFingerprint,
            createdAt: winner.createdAt,
            modifiedAt: winner.modifiedAt,
            revision: winner.revision,
            engineMode: winner.engineMode,
            source: winner.source
        )
    }

    public static func polishStylePromptFingerprint(for prompt: String) -> String {
        SHA256.hash(data: Data(prompt.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    mutating func prunePolishStylePromptSnapshots() {
        var retained: [String: String] = [:]
        var retainedCharacters = 0
        let newestEntries = entries.sorted { $0.createdAt > $1.createdAt }

        for entry in newestEntries {
            guard retained.count < Self.maxPolishStylePromptSnapshots,
                  let fingerprint = entry.polishStylePromptFingerprint,
                  retained[fingerprint] == nil,
                  let prompt = polishStylePromptSnapshots[fingerprint] else {
                continue
            }
            guard retainedCharacters + prompt.count
                    <= Self.maxPolishStylePromptSnapshotCharacters else {
                continue
            }
            retained[fingerprint] = prompt
            retainedCharacters += prompt.count
        }
        polishStylePromptSnapshots = retained
    }
}

extension SyncedSpeechHistory {
    mutating func recordClearAll(at date: Date = Date()) {
        entries.removeAll()
        polishStylePromptSnapshots.removeAll()
        clearedAt = date
    }
}
