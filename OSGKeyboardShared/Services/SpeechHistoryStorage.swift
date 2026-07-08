// SpeechHistoryStorage.swift
// OSGKeyboard · Shared
//
// Local persistence for the speech history payload (entries + tombstones).

import Foundation

public enum SpeechHistoryStorage {
    public static let storageKey = SyncedSpeechHistory.kvsKey
    /// Pre-unification iOS history in `UserDefaults.standard`.
    public static let legacyIOSEntriesKey = "speechHistory.entries.v1"
    /// Pre-unification macOS history in `UserDefaults.standard`.
    public static let legacyMacHistoryKey = "mac.history"

    public static func load(from defaults: UserDefaults) -> SyncedSpeechHistory {
        if let data = defaults.data(forKey: storageKey),
           let history = try? JSONDecoder().decode(SyncedSpeechHistory.self, from: data) {
            return history
        }
        return migrateLegacyIfNeeded(into: defaults)
    }

    public static func save(_ history: SyncedSpeechHistory, to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Import older per-platform keys once, then persist the unified payload.
    public static func migrateLegacyIfNeeded(into defaults: UserDefaults) -> SyncedSpeechHistory {
        var entries: [SpeechHistoryEntry] = []

        if let data = defaults.data(forKey: legacyIOSEntriesKey),
           let legacy = try? JSONDecoder().decode([LegacyIOSHistoryEntry].self, from: data) {
            entries.append(contentsOf: legacy.map {
                SpeechHistoryEntry(
                    id: $0.id,
                    text: $0.text,
                    createdAt: $0.createdAt,
                    engineMode: $0.engineMode
                )
            })
            defaults.removeObject(forKey: legacyIOSEntriesKey)
        }

        if let data = defaults.data(forKey: legacyMacHistoryKey),
           let legacy = try? JSONDecoder().decode([LegacyMacHistoryRecord].self, from: data) {
            entries.append(contentsOf: legacy.map {
                SpeechHistoryEntry(id: $0.id, text: $0.text, createdAt: $0.date, engineMode: nil)
            })
            defaults.removeObject(forKey: legacyMacHistoryKey)
        }

        guard !entries.isEmpty else { return .empty }

        var history = SyncedSpeechHistory(updatedAt: Date(), entries: [])
        for entry in entries {
            history.entries.append(entry)
        }
        history.entries.sort { $0.createdAt > $1.createdAt }
        history.trimEntries()
        save(history, to: defaults)
        return history
    }
}

// MARK: - Legacy decoding

private struct LegacyIOSHistoryEntry: Codable {
    let id: UUID
    let text: String
    let createdAt: Date
    let engineMode: String
}

private struct LegacyMacHistoryRecord: Codable {
    let id: UUID
    let text: String
    let date: Date
}
