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

    @discardableResult
    public func append(
        id: UUID = UUID(),
        text: String,
        engineMode: String? = nil
    ) -> SpeechHistoryEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        rebaseOnPersistedStateBeforeMutation()
        let entry = SpeechHistoryEntry(id: id, text: trimmed, engineMode: engineMode)
        payload.entries.insert(entry, at: 0)
        payload.trimEntries()
        payload.updatedAt = Date()
        applyPayload(postCloudPush: true)
        return entry
    }

    /// Apply one idempotent mutation emitted by the keyboard extension.
    @discardableResult
    public func applyHistoryMutation(_ mutation: HistoryMutation) -> SpeechHistoryEntry? {
        rebaseOnPersistedStateBeforeMutation()
        if payload.appliedMutationIDs.contains(mutation.id) {
            return payload.entries.first { $0.id == mutation.entryID }
        }

        switch mutation.action {
        case .append:
            if let existing = payload.entries.first(where: { $0.id == mutation.entryID }) {
                return existing
            }
            guard let text = mutation.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            let entry = SpeechHistoryEntry(
                id: mutation.entryID,
                text: text,
                engineMode: mutation.engineMode
            )
            payload.entries.insert(entry, at: 0)
            finishMutation(mutationID: mutation.id)
            return entry

        case .update, .restore:
            guard let text = mutation.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            guard let index = payload.entries.firstIndex(where: { $0.id == mutation.entryID })
            else {
                // The original row may have been deleted or trimmed remotely.
                let fallback = SpeechHistoryEntry(text: text, engineMode: mutation.engineMode)
                payload.entries.insert(fallback, at: 0)
                finishMutation(mutationID: mutation.id)
                return fallback
            }
            let existing = payload.entries[index]
            if let expected = mutation.expectedRevision, existing.revision != expected {
                // Never overwrite a newer cloud edit. Preserve this local result
                // as a new row instead.
                let conflictCopy = SpeechHistoryEntry(text: text, engineMode: mutation.engineMode)
                payload.entries.insert(conflictCopy, at: 0)
                finishMutation(mutationID: mutation.id)
                return conflictCopy
            }
            let updated = SpeechHistoryEntry(
                id: existing.id,
                text: text,
                createdAt: existing.createdAt,
                modifiedAt: Date(),
                revision: existing.revision + 1,
                engineMode: mutation.engineMode ?? existing.engineMode
            )
            payload.entries[index] = updated
            finishMutation(mutationID: mutation.id)
            return updated

        case .delete:
            guard payload.entries.contains(where: { $0.id == mutation.entryID }) else {
                return nil
            }
            payload.deletedEntryIDs[mutation.entryID] = Date()
            payload.entries.removeAll { $0.id == mutation.entryID }
            finishMutation(mutationID: mutation.id)
            return nil
        }
    }

    public func delete(id: UUID) {
        rebaseOnPersistedStateBeforeMutation()
        guard payload.entries.contains(where: { $0.id == id }) else { return }
        payload.deletedEntryIDs[id] = Date()
        payload.entries.removeAll { $0.id == id }
        payload.updatedAt = Date()
        payload.pruneTombstonesIfNeeded()
        applyPayload(postCloudPush: true)
    }

    /// Deletes every entry whose `createdAt` falls on the given calendar day (local).
    public func deleteEntries(on day: Date) {
        rebaseOnPersistedStateBeforeMutation()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let matching = payload.entries.filter { $0.createdAt >= start && $0.createdAt < end }
        guard !matching.isEmpty else { return }

        let now = Date()
        for entry in matching {
            payload.deletedEntryIDs[entry.id] = now
        }
        payload.entries.removeAll { $0.createdAt >= start && $0.createdAt < end }
        payload.updatedAt = now
        payload.pruneTombstonesIfNeeded()
        applyPayload(postCloudPush: true)
    }

    public func clearAll() {
        rebaseOnPersistedStateBeforeMutation()
        payload.recordClearAll()
        payload.updatedAt = Date()
        payload.pruneTombstonesIfNeeded()
        applyPayload(postCloudPush: true)
    }

    /// Cloud pulls write the merged history to disk but only *schedule* the
    /// in-memory reload (the notification observer hops through a Task).
    /// Mutating a stale snapshot and saving it wholesale would erase whatever
    /// that merge just brought in — always rebase on the persisted state
    /// before mutating.
    private func rebaseOnPersistedStateBeforeMutation() {
        let disk = SpeechHistoryStorage.load(from: defaults)
        guard disk != payload else { return }
        payload = SyncedSpeechHistory.merge(local: payload, remote: disk)
    }

    private func finishMutation(mutationID: UUID) {
        payload.appliedMutationIDs.append(mutationID)
        payload.appliedMutationIDs = Array(payload.appliedMutationIDs.suffix(256))
        payload.trimEntries()
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
        // Cloud push needs App Group settings (`settingsICloudSyncEnabled`).
        // Skip when the suite is missing (unsigned test host) so we never
        // schedule a Task that constructs `AppGroupStore()` and traps.
        guard postCloudPush, AppGroup.isAvailable else { return }
        Task {
            try? await SpeechHistoryCloudSync.shared.pushLocalIfEnabled()
        }
    }
}
