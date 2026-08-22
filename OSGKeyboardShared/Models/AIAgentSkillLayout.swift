// AIAgentSkillLayout.swift
// OSGKeyboard · Shared
//
// Enabled clipboard skills (ordered) plus which export skills the user
// confirmed a companion Shortcut for. Missing storage hydrates to every
// built-in default skill; an explicit empty list is kept
// so turning every skill off is distinct from a fresh install.

import Foundation

public struct AIAgentSkillLayout: Codable, Equatable, Sendable {
    public static let defaultEnabledIDs = AIClipboardSkillCatalog.catalog
        .filter(\.isDefault)
        .map(\.id)

    /// Keyboard chip order. Unknown and duplicate IDs are dropped on sanitize.
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

    public func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    public func hasConfirmedShortcut(_ id: String) -> Bool {
        confirmedShortcutIDs.contains(id)
    }

    /// Drops unknown IDs and duplicates. Shortcut setup is tracked separately
    /// so bundled export skills can remain visible as installed defaults.
    public func sanitized(
        catalog: [AIClipboardSkill] = AIClipboardSkillCatalog.catalog
    ) -> AIAgentSkillLayout {
        let known = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var seenEnabled = Set<String>()
        let enabled = enabledIDs.filter { id in
            known[id] != nil && seenEnabled.insert(id).inserted
        }

        var seenConfirmed = Set<String>()
        let confirmed = confirmedShortcutIDs.filter { id in
            guard known[id]?.requiresShortcut == true else { return false }
            return seenConfirmed.insert(id).inserted
        }

        return AIAgentSkillLayout(
            enabledIDs: enabled,
            confirmedShortcutIDs: confirmed
        )
    }
}

public enum AIAgentSkillEnableResult: Equatable, Sendable {
    case enabled
    case alreadyEnabled
    case needsShortcut
    case unknown
}
