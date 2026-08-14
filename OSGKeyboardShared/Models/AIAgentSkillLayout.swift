// AIAgentSkillLayout.swift
// OSGKeyboard · Shared
//
// Enabled clipboard-skill slots (max 8, ordered) plus which export skills
// the user confirmed a companion Shortcut for. Missing storage hydrates
// to the three default transform skills; an explicit empty list is kept
// so turning every skill off is distinct from a fresh install.

import Foundation

public struct AIAgentSkillLayout: Codable, Equatable, Sendable {
    public static let maximumEnabled = 8
    public static let defaultEnabledIDs = [
        AIClipboardSkillCatalog.replyID,
        AIClipboardSkillCatalog.summarizeID,
        AIClipboardSkillCatalog.translateID,
    ]

    /// Keyboard chip order. Unknown / unconfirmed IDs are dropped on sanitize.
    public var enabledIDs: [String]
    /// Export skills whose companion Shortcut the user marked as added.
    public var confirmedShortcutIDs: [String]

    public static let `default` = AIAgentSkillLayout(
        enabledIDs: defaultEnabledIDs,
        confirmedShortcutIDs: []
    )

    public init(enabledIDs: [String], confirmedShortcutIDs: [String]) {
        self.enabledIDs = enabledIDs
        self.confirmedShortcutIDs = confirmedShortcutIDs
    }

    public var isFull: Bool {
        enabledIDs.count >= Self.maximumEnabled
    }

    public func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    public func hasConfirmedShortcut(_ id: String) -> Bool {
        confirmedShortcutIDs.contains(id)
    }

    /// Drops unknown IDs, unconfirmed export skills, and duplicates; caps at 8.
    public func sanitized(
        catalog: [AIClipboardSkill] = AIClipboardSkillCatalog.catalog
    ) -> AIAgentSkillLayout {
        let known = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var seenEnabled = Set<String>()
        let enabled = enabledIDs.filter { id in
            guard let skill = known[id], seenEnabled.insert(id).inserted else { return false }
            if skill.requiresShortcut {
                return confirmedShortcutIDs.contains(id)
            }
            return true
        }
        .prefix(Self.maximumEnabled)

        var seenConfirmed = Set<String>()
        let confirmed = confirmedShortcutIDs.filter { id in
            guard known[id]?.requiresShortcut == true else { return false }
            return seenConfirmed.insert(id).inserted
        }

        return AIAgentSkillLayout(
            enabledIDs: Array(enabled),
            confirmedShortcutIDs: confirmed
        )
    }
}

public enum AIAgentSkillEnableResult: Equatable, Sendable {
    case enabled
    case alreadyEnabled
    case needsShortcut
    case full
    case unknown
}
