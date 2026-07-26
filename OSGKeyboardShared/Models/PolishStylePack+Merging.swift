// PolishStylePack+Merging.swift
// OSGKeyboard · Shared
//
// Deterministic iCloud merge rules for user-created polish style packs.

import Foundation

extension PolishStyleCatalog {
    public static let kvsKeyV2 = "polishStyles.v2"
    public static let tombstoneRetention: TimeInterval = 365 * 24 * 60 * 60
    public static let maxTombstones = 100

    public static func merge(
        local: PolishStyleCatalog,
        remote: PolishStyleCatalog
    ) -> PolishStyleCatalog {
        let clearedAt = later(local.clearedAt, remote.clearedAt)
        var tombstones = local.deletedEntryIDs
        for (id, date) in remote.deletedEntryIDs {
            tombstones[id] = max(tombstones[id] ?? .distantPast, date)
        }
        tombstones = prune(tombstones, clearedAt: clearedAt)

        var byID: [String: PolishStylePack] = [:]
        for candidate in local.entries + remote.entries {
            guard candidate.kind == .user else { continue }
            guard !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let prompt = candidate.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty, prompt.count <= PolishStyleLimits.maximumPromptCharacters else { continue }
            guard tombstones[candidate.id] == nil else { continue }
            if let clearedAt, candidate.createdAt <= clearedAt { continue }

            if let existing = byID[candidate.id] {
                byID[candidate.id] = candidate.updatedAt >= existing.updatedAt ? candidate : existing
            } else {
                byID[candidate.id] = candidate
            }
        }

        let entries = byID.values
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .prefix(PolishStyleLimits.maximumUserPacks)

        return PolishStyleCatalog(
            entries: Array(entries),
            version: max(local.version, remote.version) + 1,
            lastSyncedAt: [local.lastSyncedAt, remote.lastSyncedAt].compactMap { $0 }.max(),
            deletedEntryIDs: tombstones,
            clearedAt: clearedAt
        )
    }

    public mutating func recordClearAll(at date: Date = Date()) {
        entries.removeAll()
        clearedAt = date
        version += 1
    }

    public mutating func pruneTombstonesIfNeeded() {
        deletedEntryIDs = Self.prune(deletedEntryIDs, clearedAt: clearedAt)
    }

    private static func prune(
        _ tombstones: [String: Date],
        clearedAt: Date?
    ) -> [String: Date] {
        let cutoff = Date().addingTimeInterval(-tombstoneRetention)
        var kept = tombstones.filter { _, date in
            guard date >= cutoff else { return false }
            guard let clearedAt else { return true }
            return date > clearedAt
        }
        if kept.count > maxTombstones {
            kept = Dictionary(
                uniqueKeysWithValues: kept
                    .sorted { $0.value > $1.value }
                    .prefix(maxTombstones)
                    .map { ($0.key, $0.value) }
            )
        }
        return kept
    }

    private static func later(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): max(left, right)
        case (nil, let right?): right
        case (let left?, nil): left
        case (nil, nil): nil
        }
    }
}
