// PolishStylePack.swift
// OSGKeyboard · Shared
//
// Complete writing-personality prompts used by the polish pipeline. Built-in
// packs ship with the app; only user-created packs are persisted and synced.

import Foundation

public struct PolishStylePack: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case builtin
        case user
    }

    public let id: String
    public var name: String
    public var prompt: String
    /// When true, polish may keep model-added emoji and the prompt overrides R5.
    /// Defaults off so existing / builtin styles stay emoji-strict.
    public var allowsAddedEmoji: Bool
    public let kind: Kind
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = "user.\(UUID().uuidString.lowercased())",
        name: String,
        prompt: String,
        allowsAddedEmoji: Bool = false,
        kind: Kind = .user,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.allowsAddedEmoji = allowsAddedEmoji
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public func displayName(language: AppUILanguage? = nil) -> String {
        guard kind == .builtin else { return name }
        return SharedL10n.string("polishStyle.\(id.dropFirst("builtin.".count))", language: language)
    }

    /// Effective emoji policy for polish: explicit toggle, or a custom prompt that
    /// clearly opts in (so paste-only custom styles still keep model-added emoji).
    public var effectiveAllowsAddedEmoji: Bool {
        if allowsAddedEmoji { return true }
        guard kind == .user else { return false }
        return Self.promptDeclaresAddedEmojiOptIn(prompt)
    }

    /// Heuristic for custom prompts that declare “add mood emoji” themselves.
    public static func promptDeclaresAddedEmojiOptIn(_ prompt: String) -> Bool {
        let markers = [
            "允许新增 emoji",
            "允许新增emoji",
            "按情绪点缀",
            "按原文情绪",
            "Emoji 覆盖",
            "outranks global R5",
            "may add emojis",
            "allow mood emoji",
            "allowsAddedEmoji",
        ]
        return markers.contains { prompt.localizedCaseInsensitiveContains($0) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, allowsAddedEmoji, kind, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        // Older synced packs omit the key — stay emoji-strict.
        allowsAddedEmoji = try container.decodeIfPresent(Bool.self, forKey: .allowsAddedEmoji) ?? false
        kind = try container.decode(Kind.self, forKey: .kind)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public enum PolishStyleLimits {
    public static let maximumUserPacks = 8
    public static let maximumPromptCharacters = 6_000
}

public enum PolishStyleValidationError: Error, Equatable, Sendable {
    case emptyName
    case emptyPrompt
    case tooManyUserPacks
    case promptTooLong(maximum: Int)
    case builtinIsImmutable
}

public struct PolishStyleCatalog: Codable, Equatable, Sendable {
    public var entries: [PolishStylePack]
    public var version: Int
    public var lastSyncedAt: Date?
    /// Deletion tombstones prevent an offline device from restoring old packs.
    public var deletedEntryIDs: [String: Date]
    public var clearedAt: Date?

    public init(
        entries: [PolishStylePack] = [],
        version: Int = 1,
        lastSyncedAt: Date? = nil,
        deletedEntryIDs: [String: Date] = [:],
        clearedAt: Date? = nil
    ) {
        self.entries = entries.filter { $0.kind == .user }
        self.version = version
        self.lastSyncedAt = lastSyncedAt
        self.deletedEntryIDs = deletedEntryIDs
        self.clearedAt = clearedAt
    }

    public static let empty = PolishStyleCatalog()

    public mutating func upsert(_ pack: PolishStylePack, at date: Date = Date()) throws {
        guard pack.kind == .user else { throw PolishStyleValidationError.builtinIsImmutable }
        let name = pack.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = pack.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw PolishStyleValidationError.emptyName }
        guard !prompt.isEmpty else { throw PolishStyleValidationError.emptyPrompt }
        guard prompt.count <= PolishStyleLimits.maximumPromptCharacters else {
            throw PolishStyleValidationError.promptTooLong(maximum: PolishStyleLimits.maximumPromptCharacters)
        }

        if let index = entries.firstIndex(where: { $0.id == pack.id }) {
            var updated = pack
            updated.name = name
            updated.prompt = prompt
            updated.allowsAddedEmoji = pack.allowsAddedEmoji
            updated.updatedAt = date
            entries[index] = updated
        } else {
            guard entries.count < PolishStyleLimits.maximumUserPacks else {
                throw PolishStyleValidationError.tooManyUserPacks
            }
            var created = pack
            created.name = name
            created.prompt = prompt
            created.allowsAddedEmoji = pack.allowsAddedEmoji
            created.updatedAt = date
            entries.append(created)
        }
        deletedEntryIDs.removeValue(forKey: pack.id)
        version += 1
    }

    public mutating func recordDeletion(of id: String, at date: Date = Date()) {
        entries.removeAll { $0.id == id }
        deletedEntryIDs[id] = date
        version += 1
    }
}

public enum PolishStylePackCatalog {
    public static let defaultID = "builtin.light"
    public static let newUserPromptTemplate = """
    # 角色
    描述这个风格采用的写作人格、语气和表达习惯。

    # 风格边界
    描述这种人格最应该做什么，以及绝不能出现什么。

    # 示例
    提供一条最能代表这个风格的「输入 → 输出」示例。
    """

    /// The stable core owns ASR correction, dictionaries, and output safety.
    /// A style pack contributes personality only.
    public static func runtimePersonality(for style: PolishStylePack) -> String {
        // Older synced user packs may still contain the retired placeholder.
        style.prompt
            .replacingOccurrences(of: "{{DICTIONARY}}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Built-in packs loaded from `Resources/PolishStyles/` (manifest + per-style JSON).
    public static let builtins: [PolishStylePack] = {
        let loaded = BuiltinPolishStyleLoader.load()
        precondition(!loaded.isEmpty, "Built-in polish styles failed to load from bundle Resources/PolishStyles")
        return loaded
    }()

    /// Built-in style sections shown in the polish-styles UI.
    public enum BuiltinStyleGroup: String, CaseIterable, Sendable {
        case practical
        case fun

        public var ids: [String] {
            switch self {
            case .practical:
                return [defaultID, "builtin.structured", "builtin.formal", "builtin.chat"]
            case .fun:
                return ["builtin.dating", "builtin.flex", "builtin.corp", "builtin.diba", "builtin.xhs"]
            }
        }

        public var packs: [PolishStylePack] {
            ids.compactMap { id in builtins.first { $0.id == id } }
        }
    }

    public static func resolve(id: String, userCatalog: PolishStyleCatalog) -> PolishStylePack {
        builtins.first(where: { $0.id == id })
            ?? userCatalog.entries.first(where: { $0.id == id })
            ?? builtins[0]
    }

    public static func all(userCatalog: PolishStyleCatalog) -> [PolishStylePack] {
        builtins + userCatalog.entries.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    public static func isValidActiveID(_ id: String, userCatalog: PolishStyleCatalog) -> Bool {
        builtins.contains(where: { $0.id == id }) || userCatalog.entries.contains(where: { $0.id == id })
    }

    /// Fun personality packs that fully rewrite voice (dating / flex / corp / diba / xhs).
    public static func isFunPersonality(id: String) -> Bool {
        BuiltinStyleGroup.fun.ids.contains(id)
    }

    /// Heavy fun styles bypass practical safeguards and use only the shared
    /// transcript formatter before their personality prompt.
    public static func usesFormattingOnlyPipeline(
        id: String,
        intensity: PolishIntensity
    ) -> Bool {
        intensity == .heavy && isFunPersonality(id: id)
    }

    /// SF Symbol shown on polish-style cards (built-in and user packs).
    public static func systemImage(for id: String) -> String {
        switch id {
        case "builtin.structured": return "list.bullet.rectangle"
        case "builtin.formal": return "briefcase"
        case "builtin.dating": return "heart.text.square"
        case "builtin.chat": return "bubble.left.and.bubble.right"
        case "builtin.light": return "wand.and.sparkles"
        case "builtin.flex": return "textformat"
        case "builtin.corp": return "building.2"
        case "builtin.diba": return "quote.bubble"
        case "builtin.xhs": return "star.bubble"
        default: return "text.badge.star"
        }
    }
}
