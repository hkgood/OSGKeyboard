// ClipboardHistoryStore.swift
// OSGKeyboard · Shared
//
// App Group–backed clipboard history (local only; not iCloud-synced).

import Foundation
import Combine

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    public static let shared = ClipboardHistoryStore()

    public enum Keys {
        public static let entries = "clipboard.history.v1"
        public static let lastChangeCount = "clipboard.history.lastChangeCount"
        public static let suggestionDismissedChangeCount =
            "clipboard.history.suggestionDismissedChangeCount"
    }

    @Published public private(set) var entries: [ClipboardHistoryEntry] = []

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if let suite = AppGroup.defaultsIfAvailable {
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
        entries = Self.loadEntries(from: self.defaults)
    }

    public var lastObservedChangeCount: Int {
        get { defaults.integer(forKey: Keys.lastChangeCount) }
        set { defaults.set(newValue, forKey: Keys.lastChangeCount) }
    }

    public var suggestionDismissedChangeCount: Int? {
        get {
            guard defaults.object(forKey: Keys.suggestionDismissedChangeCount) != nil else {
                return nil
            }
            return defaults.integer(forKey: Keys.suggestionDismissedChangeCount)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.suggestionDismissedChangeCount)
            } else {
                defaults.removeObject(forKey: Keys.suggestionDismissedChangeCount)
            }
        }
    }

    /// Inserts accepted text (dedupe + pin). Returns the new head when stored.
    @discardableResult
    public func ingest(
        rawText: String?,
        changeCount: Int?
    ) -> ClipboardHistoryEntry? {
        guard let text = ClipboardHistoryPolicy.acceptedText(from: rawText) else {
            return nil
        }
        let entry = ClipboardHistoryEntry(text: text, changeCount: changeCount)
        entries = ClipboardHistoryPolicy.merging(incoming: entry, into: entries)
        persist()
        if let changeCount {
            lastObservedChangeCount = changeCount
            // New content clears a previous suggestion dismiss for that older change.
            if suggestionDismissedChangeCount != changeCount {
                suggestionDismissedChangeCount = nil
            }
        }
        return entry
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func clearAll() {
        entries = []
        persist()
    }

    public func reload() {
        entries = Self.loadEntries(from: defaults)
    }

    public var newestEntry: ClipboardHistoryEntry? {
        entries.first
    }

    /// Whether the suggestion strip should offer `newestEntry` for this changeCount.
    public func shouldShowSuggestion(
        forChangeCount changeCount: Int?,
        candidateBarEnabled: Bool,
        historyEnabled: Bool
    ) -> Bool {
        guard historyEnabled, candidateBarEnabled else { return false }
        guard newestEntry != nil else { return false }
        if let changeCount,
           let dismissed = suggestionDismissedChangeCount,
           dismissed == changeCount {
            return false
        }
        return true
    }

    public func dismissSuggestion(forChangeCount changeCount: Int?) {
        if let changeCount {
            suggestionDismissedChangeCount = changeCount
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Keys.entries)
        } catch {
            OSGLog.config.warning(
                "clipboard history encode failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private static func loadEntries(from defaults: UserDefaults) -> [ClipboardHistoryEntry] {
        guard let data = defaults.data(forKey: Keys.entries) else { return [] }
        do {
            let decoded = try JSONDecoder().decode([ClipboardHistoryEntry].self, from: data)
            return Array(decoded.prefix(ClipboardHistoryPolicy.maxEntries))
        } catch {
            OSGLog.config.warning(
                "clipboard history decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
