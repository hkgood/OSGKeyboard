// PersonalDictionary.swift
// OSGKeyboard · Shared
//
// User-curated list of terms the LLM must never rewrite. Persisted
// in the App Group (JSON-encoded) so both the main app's Settings
// UI and the keyboard extension's LLM call read the same data.
//
// Sources (mutually exclusive per entry):
//   - `.manual`     user typed it in by hand
//   - `.history`    auto-extracted from the user's transcription
//                   history by `DictionaryLearner`
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

    public init(entries: [Entry] = [], version: Int = 1) {
        self.entries = entries
        self.version = version
    }

    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public var term: String
        public var aliases: [String]
        public var category: Category
        public var source: Source
        public var createdAt: Date
        public var usageCount: Int

        public init(
            id: UUID = UUID(),
            term: String,
            aliases: [String] = [],
            category: Category,
            source: Source,
            createdAt: Date = Date(),
            usageCount: Int = 0
        ) {
            self.id = id
            self.term = term
            self.aliases = aliases
            self.category = category
            self.source = source
            self.createdAt = createdAt
            self.usageCount = usageCount
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

extension PersonalDictionary {
    public static let empty = PersonalDictionary()

    /// Renders the entire dictionary as a prompt fragment. Entries
    /// are grouped by category so the LLM can scan quickly. Empty
    /// dictionary returns "" so the caller can blindly concatenate.
    public func promptFragment() -> String {
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
