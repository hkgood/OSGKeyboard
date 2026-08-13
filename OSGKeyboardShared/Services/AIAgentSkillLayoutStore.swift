// AIAgentSkillLayoutStore.swift
// OSGKeyboard · Shared
//
// Observable facade over the persisted skill layout. The Skills tab mutates
// this; the keyboard reads the same App Group snapshot on each config poll.

import Foundation
import Combine

@MainActor
public final class AIAgentSkillLayoutStore: ObservableObject {
    public static let shared = AIAgentSkillLayoutStore()

    @Published public private(set) var layout: AIAgentSkillLayout

    private let defaults: UserDefaults?
    private let persist: (AIAgentSkillLayout) -> Void
    private let load: () -> AIAgentSkillLayout

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
            self.load = { AppGroupStore(defaults: defaults).agentSkillLayout }
            self.persist = { AppGroupStore(defaults: defaults).setAgentSkillLayout($0) }
        } else {
            self.defaults = nil
            self.load = { AppGroupStore().agentSkillLayout }
            self.persist = { AppGroupStore().setAgentSkillLayout($0) }
        }
        self.layout = self.load()
    }

    public func reload() {
        layout = load()
    }

    public var enabledSkills: [AIClipboardSkill] {
        AIClipboardSkillCatalog.visible(enabledIDs: layout.enabledIDs)
    }

    public var availableSkills: [AIClipboardSkill] {
        AIClipboardSkillCatalog.catalog.filter { !layout.isEnabled($0.id) }
    }

    @discardableResult
    public func enable(_ id: String) -> AIAgentSkillEnableResult {
        let current = layout.sanitized()
        guard let skill = AIClipboardSkillCatalog.skill(id: id) else { return .unknown }
        if current.isEnabled(id) { return .alreadyEnabled }
        if skill.requiresShortcut, !current.hasConfirmedShortcut(id) {
            return .needsShortcut
        }
        if current.isFull { return .full }
        commit(
            AIAgentSkillLayout(
                enabledIDs: current.enabledIDs + [id],
                confirmedShortcutIDs: current.confirmedShortcutIDs
            )
        )
        return .enabled
    }

    /// Drops the keyboard slot only. Companion Shortcuts stay installed;
    /// the user deletes them in the Shortcuts app if they want them gone.
    public func disable(_ id: String) {
        let current = layout.sanitized()
        commit(
            AIAgentSkillLayout(
                enabledIDs: current.enabledIDs.filter { $0 != id },
                confirmedShortcutIDs: current.confirmedShortcutIDs
            )
        )
    }

    /// Marks the companion Shortcut as added, then tries to occupy a slot.
    @discardableResult
    public func confirmShortcutAndEnable(_ id: String) -> AIAgentSkillEnableResult {
        guard let skill = AIClipboardSkillCatalog.skill(id: id), skill.requiresShortcut else {
            return .unknown
        }
        var current = layout.sanitized()
        if !current.confirmedShortcutIDs.contains(id) {
            current.confirmedShortcutIDs.append(id)
        }
        commit(current)
        return enable(id)
    }

    public func moveEnabled(id draggedID: String, onto targetID: String) {
        var ids = layout.sanitized().enabledIDs
        guard let from = ids.firstIndex(of: draggedID),
              let to = ids.firstIndex(of: targetID),
              from != to else { return }
        ids.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
        commit(
            AIAgentSkillLayout(
                enabledIDs: ids,
                confirmedShortcutIDs: layout.confirmedShortcutIDs
            )
        )
    }

    private func commit(_ layout: AIAgentSkillLayout) {
        persist(layout)
        self.layout = load()
    }
}
