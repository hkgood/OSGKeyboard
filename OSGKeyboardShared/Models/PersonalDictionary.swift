// PersonalDictionary.swift
// OSGKeyboard · Shared
//
// User-curated list of terms the LLM must never rewrite. Persisted
// in the App Group (JSON-encoded) so both the main app's Settings
// UI and the keyboard extension's LLM call read the same data.
//
// Sources (mutually exclusive per entry):
//   - `.manual`     user typed it in by hand
//   - `.history`    legacy auto-learned entries (migrated to `.manual`)
//   - `.contacts`   imported from the iOS Contacts framework
//   - `.recentEdit` extracted from edits the user made to a
//                   polished transcript before sending
//
// The dictionary is intentionally read-mostly: writes only happen
// from the main app (or from a low-frequency background task). The
// keyboard extension never writes to it.

import Foundation

public struct PersonalDictionary: Codable, Sendable, Equatable {
    public var entries: [Entry]
    public var version: Int
    /// When this dictionary blob was last successfully pushed to iCloud KVS.
    public var lastSyncedAt: Date?
    /// Tombstones for deleted entries — prevents remote resurrections.
    public var deletedEntryIDs: [UUID: Date]
    /// When set, entries created at or before this instant are excluded from merge.
    public var clearedAt: Date?

    public init(
        entries: [Entry] = [],
        version: Int = 1,
        lastSyncedAt: Date? = nil,
        deletedEntryIDs: [UUID: Date] = [:],
        clearedAt: Date? = nil
    ) {
        self.entries = entries
        self.version = version
        self.lastSyncedAt = lastSyncedAt
        self.deletedEntryIDs = deletedEntryIDs
        self.clearedAt = clearedAt
    }

    private enum CodingKeys: String, CodingKey {
        case entries
        case version
        case lastSyncedAt
        case deletedEntryIDs
        case clearedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        deletedEntryIDs = try container.decodeIfPresent([UUID: Date].self, forKey: .deletedEntryIDs) ?? [:]
        clearedAt = try container.decodeIfPresent(Date.self, forKey: .clearedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        if !deletedEntryIDs.isEmpty {
            try container.encode(deletedEntryIDs, forKey: .deletedEntryIDs)
        }
        try container.encodeIfPresent(clearedAt, forKey: .clearedAt)
    }

    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public var term: String
        public var aliases: [String]
        public var category: Category
        public var source: Source
        public var createdAt: Date
        /// Last mutation time — used for iCloud merge conflict resolution.
        public var updatedAt: Date
        public var usageCount: Int

        public init(
            id: UUID = UUID(),
            term: String,
            aliases: [String] = [],
            category: Category,
            source: Source,
            createdAt: Date = Date(),
            updatedAt: Date? = nil,
            usageCount: Int = 0
        ) {
            self.id = id
            self.term = term
            self.aliases = aliases
            self.category = category
            self.source = source
            self.createdAt = createdAt
            self.updatedAt = updatedAt ?? createdAt
            self.usageCount = usageCount
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case term
            case aliases
            case category
            case source
            case createdAt
            case updatedAt
            case usageCount
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            term = try container.decode(String.self, forKey: .term)
            aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
            category = try container.decode(Category.self, forKey: .category)
            source = try container.decode(Source.self, forKey: .source)
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
            usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(term, forKey: .term)
            try container.encode(aliases, forKey: .aliases)
            try container.encode(category, forKey: .category)
            try container.encode(source, forKey: .source)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try container.encode(usageCount, forKey: .usageCount)
        }

        public enum Category: String, Codable, Sendable, CaseIterable {
            /// Person / place / brand / organization.
            case properNoun
            /// API, framework, library, language, file format.
            case technical
            /// Initialism like LLM, iOS, ML.
            case acronym
            /// Product name (Typeless, OSGKeyboard, ChatGPT).
            case productName
            /// Anything that does not fit the above.
            case custom

            public var labelKey: String {
                switch self {
                case .properNoun: return "dict.category.properNoun"
                case .technical: return "dict.category.technical"
                case .acronym: return "dict.category.acronym"
                case .productName: return "dict.category.productName"
                case .custom: return "dict.category.custom"
                }
            }
        }

        public enum Source: String, Codable, Sendable, CaseIterable {
            case manual
            case history
            case contacts
            case recentEdit

            public var labelKey: String {
                switch self {
                case .manual: return "dict.source.manual"
                case .history: return "dict.source.history"
                case .contacts: return "dict.source.contacts"
                case .recentEdit: return "dict.source.recentEdit"
                }
            }
        }

        /// Renders the entry for the LLM prompt. Includes aliases
        /// in parentheses so the LLM recognizes voice variants
        /// ("k8s" → "Kubernetes") without renaming.
        public func promptFragment() -> String {
            if aliases.isEmpty { return term }
            return "\(term)（\(aliases.joined(separator: " / "))）"
        }
    }
}

extension PersonalDictionary.Entry {
    /// Lightweight category inference for manual adds and the history
    /// learner. Users can re-classify later from Settings.
    public static func inferCategory(for term: String) -> Category {
        let hasUpper = term.contains(where: { $0.isUppercase })
        let hasDigit = term.unicodeScalars.contains { scalar in
            CharacterSet.decimalDigits.contains(scalar) && scalar.isASCII
        }
        let hasLatin = term.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && scalar.isASCII
        }
        if hasUpper, !term.contains(where: { $0.isLowercase }) {
            return .acronym
        }
        if hasDigit {
            return .productName
        }
        if !hasLatin {
            return .properNoun
        }
        return .productName
    }
}

extension PersonalDictionary {
    public static let empty = PersonalDictionary()

    /// Built-in terms always included in LLM prompts. Never persisted
    /// and never shown in the Settings personal-dictionary UI.
    public static let systemEntries: [Entry] = [
        Entry(
            id: UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!,
            term: "OSGKeyboard",
            aliases: [],
            category: .productName,
            source: .manual,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            usageCount: 0
        ),
    ]

    /// User entries plus built-in system terms (deduped by term).
    public var effectiveEntries: [Entry] {
        var merged = Self.systemEntries
        let systemTerms = Set(Self.systemEntries.map { $0.term.lowercased() })
        for entry in entries where !systemTerms.contains(entry.term.lowercased()) {
            merged.append(entry)
        }
        return merged
    }

    /// Case-insensitive lookup by canonical term.
    public func entry(matchingTerm term: String) -> Entry? {
        let key = term.lowercased()
        return entries.first { $0.term.lowercased() == key }
    }

    /// Insert or update a manual entry. Returns the saved entry.
    @discardableResult
    public mutating func upsertManual(
        term: String,
        existingID: UUID? = nil,
        regenerateAliases: Bool = false
    ) -> Entry? {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let category = Entry.inferCategory(for: trimmed)

        if let existingID,
           let idx = entries.firstIndex(where: { $0.id == existingID }) {
            var entry = entries[idx]
            let termChanged = entry.term.caseInsensitiveCompare(trimmed) != .orderedSame
            entry.term = trimmed
            entry.category = category
            entry.source = .manual
            if termChanged || regenerateAliases {
                entry.aliases = []
            }
            entry.updatedAt = Date()
            entries[idx] = entry
            return entry
        }

        if let idx = entries.firstIndex(where: {
            $0.term.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            var entry = entries[idx]
            entry.term = trimmed
            entry.category = category
            entry.source = .manual
            entry.updatedAt = Date()
            entries[idx] = entry
            return entry
        }

        let now = Date()
        let entry = Entry(
            term: trimmed,
            aliases: [],
            category: category,
            source: .manual,
            createdAt: now,
            updatedAt: now
        )
        entries.append(entry)
        return entry
    }

    public mutating func updateAliases(for entryID: UUID, aliases: [String]) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let cleaned = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let termLower = entries[idx].term.lowercased()
        entries[idx].aliases = Array(
            Set(cleaned.filter { $0.lowercased() != termLower })
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        entries[idx].updatedAt = Date()
    }

    /// Renders the entire dictionary as a prompt fragment. Entries
    /// are grouped by category so the LLM can scan quickly. Empty
    /// dictionary returns "" so the caller can blindly concatenate.
    public func promptFragment() -> String {
        let entries = effectiveEntries
        guard !entries.isEmpty else { return "" }
        let grouped = Dictionary(grouping: entries, by: { $0.category })
        var lines: [String] = []
        for category in Entry.Category.allCases {
            guard let bucket = grouped[category], !bucket.isEmpty else { continue }
            let terms = bucket
                .sorted { $0.usageCount > $1.usageCount }
                .map { $0.promptFragment() }
                .joined(separator: "、")
            lines.append("【\(category.rawValue)】\(terms)")
        }
        guard !lines.isEmpty else { return "" }
        return (
            "以下为用户专有词汇，**必须**原样保留，**绝不**改写或翻译：" +
            "\n" + lines.joined(separator: "\n")
        )
    }
}
