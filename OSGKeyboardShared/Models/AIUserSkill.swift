// AIUserSkill.swift
// OSGKeyboard · Shared
//
// User-created clipboard skills. Built-in skills stay in
// `AIClipboardSkillCatalog`; this catalog is persisted in App Group so the
// keyboard can resolve custom names, prompts, and Shortcut run names.

import Foundation

public struct AIUserSkill: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    /// Card subtitle. Empty is allowed; the UI shows a generic fallback.
    public var summary: String
    public var systemImage: String
    public var prompt: String
    public var shortcutICloudURL: URL
    /// Name used by `shortcuts://run-shortcut?name=`. Independent of `name`.
    public var shortcutName: String
    /// Per-skill reasoning. Built-in skills are always off; custom defaults off.
    public var thinkingEnabled: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = "user.\(UUID().uuidString.lowercased())",
        name: String,
        summary: String = "",
        systemImage: String = AIUserSkillLimits.defaultSystemImage,
        prompt: String,
        shortcutICloudURL: URL,
        shortcutName: String,
        thinkingEnabled: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.systemImage = systemImage
        self.prompt = prompt
        self.shortcutICloudURL = shortcutICloudURL
        self.shortcutName = shortcutName
        self.thinkingEnabled = thinkingEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public var isUserCreated: Bool { id.hasPrefix("user.") }

    public func asClipboardSkill() -> AIClipboardSkill {
        AIClipboardSkill(
            id: id,
            systemImage: systemImage,
            titleKey: "",
            cardTitleKey: "",
            descriptionKey: "",
            kind: .export,
            isDefault: false,
            shortcutName: shortcutName,
            shortcutICloudURL: shortcutICloudURL,
            customName: name,
            customSummary: summary,
            customPrompt: prompt,
            thinkingEnabled: thinkingEnabled
        )
    }
}

public enum AIUserSkillLimits {
    public static let defaultSystemImage = "sparkles"
    public static let maximumPromptCharacters = 6_000
    public static let maximumNameCharacters = 40
    public static let maximumSummaryCharacters = 200
    public static let newPromptTemplate = """
    请根据剪贴板内容完成以下操作。
    只输出结果，不要解释或客套。
    """

    /// Curated SF Symbols for the skill-icon picker.
    public static let symbolChoices: [String] = [
        "sparkles",
        "wand.and.stars",
        "text.badge.checkmark",
        "checklist",
        "calendar",
        "envelope.fill",
        "bubble.left.and.bubble.right.fill",
        "character.bubble.fill",
        "doc.text.magnifyingglass",
        "arrowshape.turn.up.left.fill",
        "lightbulb.fill",
        "star.fill",
        "heart.fill",
        "flag.fill",
        "tag.fill",
        "folder.fill",
        "list.bullet",
        "square.and.pencil",
        "scissors",
        "globe",
        "paperplane.fill",
        "clock.fill",
        "bell.fill",
        "bookmark.fill",
        "person.fill",
        "link",
        "number",
        "at",
        "tray.fill",
        "quote.bubble.fill",
    ]
}

public enum AIUserSkillValidationError: Error, Equatable, Sendable {
    case emptyName
    case emptyPrompt
    case emptyShortcutName
    case invalidShortcutLink
    case emptyIcon
    case promptTooLong(maximum: Int)
}

public struct AIUserSkillCatalog: Codable, Equatable, Sendable {
    public var entries: [AIUserSkill]

    public init(entries: [AIUserSkill] = []) {
        self.entries = entries.filter(\.isUserCreated)
    }

    public static let empty = AIUserSkillCatalog()

    public func skill(id: String) -> AIUserSkill? {
        entries.first { $0.id == id }
    }

    public mutating func upsert(_ skill: AIUserSkill, at date: Date = Date()) throws {
        let name = skill.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = skill.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = skill.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortcutName = skill.shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let icon = skill.systemImage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard skill.isUserCreated else { throw AIUserSkillValidationError.emptyName }
        guard !name.isEmpty else { throw AIUserSkillValidationError.emptyName }
        guard !prompt.isEmpty else { throw AIUserSkillValidationError.emptyPrompt }
        guard prompt.count <= AIUserSkillLimits.maximumPromptCharacters else {
            throw AIUserSkillValidationError.promptTooLong(
                maximum: AIUserSkillLimits.maximumPromptCharacters
            )
        }
        guard !shortcutName.isEmpty else { throw AIUserSkillValidationError.emptyShortcutName }
        guard AIShortcutShareLink.isValid(skill.shortcutICloudURL) else {
            throw AIUserSkillValidationError.invalidShortcutLink
        }
        guard !icon.isEmpty else { throw AIUserSkillValidationError.emptyIcon }

        var saved = skill
        saved.name = String(name.prefix(AIUserSkillLimits.maximumNameCharacters))
        saved.summary = String(summary.prefix(AIUserSkillLimits.maximumSummaryCharacters))
        saved.prompt = prompt
        saved.shortcutName = shortcutName
        saved.systemImage = icon
        saved.thinkingEnabled = skill.thinkingEnabled
        saved.updatedAt = date

        if let index = entries.firstIndex(where: { $0.id == skill.id }) {
            entries[index] = saved
        } else {
            entries.append(saved)
        }
    }

    public mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }
}
