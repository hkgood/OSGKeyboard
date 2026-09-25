// ClipboardHistoryStore.swift
// OSGKeyboard · Shared
//
// App Group–backed clipboard history (local only; not iCloud-synced).

import Combine
import Foundation

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    public static let shared = ClipboardHistoryStore()

    public enum Keys {
        public static let entries = "clipboard.history.v1"
        public static let lastChangeCount = "clipboard.history.lastChangeCount"
        public static let suggestionDismissedChangeCount =
            "clipboard.history.suggestionDismissedChangeCount"
        public static let lastAutoRepliedChangeCount =
            "clipboard.history.lastAutoRepliedChangeCount"
        public static let lastAutoRepliedTextHash =
            "clipboard.history.lastAutoRepliedTextHash"
        public static let lastAutoRepliedAt =
            "clipboard.history.lastAutoRepliedAt"
        /// Bumped on every `persist()`. Lets an instance tell the notification
        /// its own write just posted from one a peer process posted.
        public static let revision = "clipboard.history.revision"
    }

    @Published public private(set) var entries: [ClipboardHistoryEntry] = []

    private let defaults: UserDefaults
    /// Installed by `startObservingCrossProcessChanges()`. Stays nil in the
    /// transient readers that construct a store just to read the newest entry.
    private var crossProcessObserver: FlowSessionDarwinObserver?
    /// Revision this instance last wrote or read, so the observer can ignore
    /// the notification its own `persist()` posted.
    private var lastSeenRevision: Int

    public init(defaults: UserDefaults? = nil) {
        let resolved: UserDefaults
        if let defaults {
            resolved = defaults
        } else if let suite = AppGroup.defaultsIfAvailable {
            resolved = suite
        } else {
            resolved = .standard
        }
        self.defaults = resolved
        lastSeenRevision = resolved.integer(forKey: Keys.revision)
        entries = Self.loadEntries(from: resolved)
    }

    /// Reloads whenever the peer process writes history.
    ///
    /// Idempotent. Call it from the long-lived owners only — the keyboard's
    /// capture coordinator and the host's foreground activation — never from a
    /// transient reader, which would register and tear down an observer per read.
    ///
    /// This does **not** replace reloading when the host returns to the
    /// foreground: Darwin notifications are dropped for a suspended process, so
    /// everything the keyboard wrote while the host was backgrounded arrives
    /// only through that reload.
    public func startObservingCrossProcessChanges() {
        guard crossProcessObserver == nil else { return }
        crossProcessObserver = FlowSessionDarwinObserver(
            notificationName: ClipboardHistoryDarwin.notificationName
        ) { [weak self] in
            self?.reloadIfPeerWrote()
        }
    }

    private func reloadIfPeerWrote() {
        guard defaults.integer(forKey: Keys.revision) != lastSeenRevision else { return }
        reload()
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

    /// Pasteboard generation whose replyable text auto mode already routed into
    /// the Reply flow. App Group–backed so a single copy triggers auto-reply at
    /// most once, even across keyboard close/reopen.
    public var lastAutoRepliedChangeCount: Int? {
        get {
            guard defaults.object(forKey: Keys.lastAutoRepliedChangeCount) != nil else {
                return nil
            }
            return defaults.integer(forKey: Keys.lastAutoRepliedChangeCount)
        }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.lastAutoRepliedChangeCount)
            } else {
                defaults.removeObject(forKey: Keys.lastAutoRepliedChangeCount)
            }
        }
    }

    /// Fingerprint of the content auto mode last routed. Universal Clipboard
    /// re-announces one copy under several changeCounts, so changeCount alone
    /// cannot stop repeat triggers for identical content.
    public var lastAutoRepliedTextHash: String? {
        get { defaults.string(forKey: Keys.lastAutoRepliedTextHash) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.lastAutoRepliedTextHash)
            } else {
                defaults.removeObject(forKey: Keys.lastAutoRepliedTextHash)
            }
        }
    }

    /// When the last auto action fired. Combined with the text fingerprint this
    /// bounds repeat triggers: identical content re-fires only after the window.
    public var lastAutoRepliedAt: Date? {
        get { defaults.object(forKey: Keys.lastAutoRepliedAt) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Keys.lastAutoRepliedAt)
            } else {
                defaults.removeObject(forKey: Keys.lastAutoRepliedAt)
            }
        }
    }

    /// Records that auto mode routed `text` (pasteboard generation
    /// `changeCount`) into a flow at `at`.
    public func markAutoReplied(text: String, changeCount: Int, at: Date = Date()) {
        lastAutoRepliedChangeCount = changeCount
        lastAutoRepliedTextHash = ClipboardHistoryPolicy.contentFingerprint(for: text)
        lastAutoRepliedAt = at
    }

    /// Whether identical content already fired inside the suppression window.
    public func recentlyAutoReplied(text: String, now: Date = Date()) -> Bool {
        guard let firedAt = lastAutoRepliedAt,
              ClipboardHistoryPolicy.isRepeatSuppressed(firedAt: firedAt, now: now)
        else { return false }
        return lastAutoRepliedTextHash == ClipboardHistoryPolicy.contentFingerprint(for: text)
    }

    /// Inserts accepted text (dedupe + pin). Returns the new head when stored.
    @discardableResult
    public func ingest(
        rawText: String?,
        changeCount: Int?
    ) -> ClipboardHistoryEntry? {
        let sanitized = ClipboardHistoryPolicy.sanitizedEntries(entries)
        if sanitized != entries {
            entries = sanitized
            persist()
        }
        guard let text = ClipboardHistoryPolicy.acceptedText(from: rawText) else {
            return nil
        }
        let entry = ClipboardHistoryEntry(text: text, changeCount: changeCount)
        let merged = ClipboardHistoryPolicy.merging(incoming: entry, into: entries)
        let bounded = ClipboardHistoryPolicy.sanitizedEntries(merged)
        guard bounded.first?.id == entry.id else {
            return nil
        }
        entries = bounded
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
        lastSeenRevision = defaults.integer(forKey: Keys.revision)
        entries = Self.loadEntries(from: defaults)
    }

    public var newestEntry: ClipboardHistoryEntry? {
        entries.first
    }

    /// Newest entry still inside the AI clipboard-hint window, if any.
    public func newestAIHintEligibleEntry(now: Date = Date()) -> ClipboardHistoryEntry? {
        guard let newest = newestEntry,
              ClipboardHistoryPolicy.isEligibleForAIHint(newest, now: now)
        else { return nil }
        return newest
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
            // Tell the peer before it can overwrite this blob from a stale copy.
            let revision = defaults.integer(forKey: Keys.revision) &+ 1
            defaults.set(revision, forKey: Keys.revision)
            lastSeenRevision = revision
            ClipboardHistoryDarwin.postHistoryChanged()
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
            let sanitized = ClipboardHistoryPolicy.sanitizedEntries(decoded)
            if sanitized != decoded, let cleanedData = try? JSONEncoder().encode(sanitized) {
                defaults.set(cleanedData, forKey: Keys.entries)
            }
            return sanitized
        } catch {
            OSGLog.config.warning(
                "clipboard history decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
