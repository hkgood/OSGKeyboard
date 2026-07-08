// SpeechHistoryStore.swift
// OSGKeyboard · Shared
//
// Observable store for voice transcription history. Mirrored through
// iCloud KVS when settings sync is enabled.

import Combine
import Foundation

@MainActor
public final class SpeechHistoryStore: ObservableObject {
    public static let shared = SpeechHistoryStore()

    @Published public private(set) var entries: [SpeechHistoryEntry] = []

    public let defaults: UserDefaults
    private var payload: SyncedSpeechHistory = .empty

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadFromDisk()
        NotificationCenter.default.addObserver(
            forName: .speechHistoryDidSyncFromCloud,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
    }

    public func append(text: String, engineMode: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = SpeechHistoryEntry(text: trimmed, engineMode: engineMode)
        payload.entries.insert(entry, at: 0)
        payload.trimEntries()
        payload.updatedAt = Date()
        applyPayload(postCloudPush: true)
    }

    public func delete(id: UUID) {
        guard payload.entries.contains(where: { $0.id == id }) else { return }
        payload.deletedEntryIDs[id] = Date()
        payload.entries.removeAll { $0.id == id }
        payload.updatedAt = Date()
        payload.pruneTombstonesIfNeeded()
        applyPayload(postCloudPush: true)
    }

    public func clearAll() {
        payload.recordClearAll()
        payload.updatedAt = Date()
        payload.pruneTombstonesIfNeeded()
        applyPayload(postCloudPush: true)
    }

    public func snapshot() -> SyncedSpeechHistory {
        payload
    }

    public func apply(_ history: SyncedSpeechHistory) {
        payload = history
        entries = history.entries.sorted { $0.createdAt > $1.createdAt }
    }

    public func reloadFromDisk() {
        payload = SpeechHistoryStorage.load(from: defaults)
        entries = payload.entries.sorted { $0.createdAt > $1.createdAt }
    }

    /// Entries grouped by calendar day (newest day first).
    public var groupedByDay: [(day: Date, items: [SpeechHistoryEntry])] {
        let calendar = Calendar.current
        var buckets: [Date: [SpeechHistoryEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.createdAt)
            buckets[day, default: []].append(entry)
        }
        return buckets.keys.sorted(by: >).map { day in
            (day, buckets[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }

    private func applyPayload(postCloudPush: Bool) {
        entries = payload.entries.sorted { $0.createdAt > $1.createdAt }
        SpeechHistoryStorage.save(payload, to: defaults)
        guard postCloudPush else { return }
        Task {
            try? await SpeechHistoryCloudSync.shared.pushLocalIfEnabled()
        }
    }
}
