// SpeechHistoryStore.swift
// OSGKeyboard · Main App
//
// Local-only log of successful voice transcriptions (Flow + future paths).

import Foundation
import Combine

struct SpeechHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    let engineMode: String

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), engineMode: String) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.engineMode = engineMode
    }
}

@MainActor
final class SpeechHistoryStore: ObservableObject {
    static let shared = SpeechHistoryStore()

    @Published private(set) var entries: [SpeechHistoryEntry] = []

    private let defaults: UserDefaults
    private let storageKey = "speechHistory.entries.v1"
    private let maxEntries = 500

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func append(text: String, engineMode: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = SpeechHistoryEntry(text: trimmed, engineMode: engineMode)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    /// Append history and update cumulative home-screen usage stats.
    func recordUtterance(
        text: String,
        engineMode: String,
        duration: TimeInterval,
        wasTranslation: Bool
    ) {
        append(text: text, engineMode: engineMode)
        UsageStatisticsStore.shared.recordUtterance(
            text: text,
            duration: duration,
            wasTranslation: wasTranslation
        )
    }

    func delete(id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        entries.removeAll()
        persist()
    }

    /// Entries grouped by calendar day (newest day first).
    var groupedByDay: [(day: Date, items: [SpeechHistoryEntry])] {
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

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([SpeechHistoryEntry].self, from: data)
        } catch {
            entries = []
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
