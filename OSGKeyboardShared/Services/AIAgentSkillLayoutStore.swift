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
    @Published public private(set) var userCatalog: AIUserSkillCatalog

    private let persistLayout: (AIAgentSkillLayout) -> Void
    private let persistUserCatalog: (AIUserSkillCatalog) -> Void
    private let loadLayout: () -> AIAgentSkillLayout
    private let loadUserCatalog: () -> AIUserSkillCatalog

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.loadUserCatalog = { AppGroupStore(defaults: defaults).agentUserSkillCatalog }
            self.persistUserCatalog = { AppGroupStore(defaults: defaults).setAgentUserSkillCatalog($0) }
            self.loadLayout = { AppGroupStore(defaults: defaults).agentSkillLayout }
            self.persistLayout = { AppGroupStore(defaults: defaults).setAgentSkillLayout($0) }
        } else {
            self.loadUserCatalog = { AppGroupStore().agentUserSkillCatalog }
            self.persistUserCatalog = { AppGroupStore().setAgentUserSkillCatalog($0) }
            self.loadLayout = { AppGroupStore().agentSkillLayout }
            self.persistLayout = { AppGroupStore().setAgentSkillLayout($0) }
        }
        self.userCatalog = self.loadUserCatalog()
        self.layout = self.loadLayout()
    }

    public func reload() {
        userCatalog = loadUserCatalog()
        layout = loadLayout()
    }

    public var mergedCatalog: [AIClipboardSkill] {
        AIClipboardSkillCatalog.all(userCatalog: userCatalog)
    }

    public var enabledSkills: [AIClipboardSkill] {
        AIClipboardSkillCatalog.visible(
            enabledIDs: layout.enabledIDs,
            userCatalog: userCatalog
        )
    }

    public var availableSkills: [AIClipboardSkill] {
        mergedCatalog.filter { !layout.isEnabled($0.id) }
    }

    public func userSkill(id: String) -> AIUserSkill? {
        userCatalog.skill(id: id)
    }

    @discardableResult
    public func enable(_ id: String) -> AIAgentSkillEnableResult {
        let current = layout.sanitized(catalog: mergedCatalog)
        guard let skill = AIClipboardSkillCatalog.skill(id: id, userCatalog: userCatalog) else {
            return .unknown
        }
        if current.isEnabled(id) { return .alreadyEnabled }
        if skill.requiresShortcut, !current.hasConfirmedShortcut(id) {
            return .needsShortcut
        }
        if current.isFull { return .full }
        commitLayout(
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
        let current = layout.sanitized(catalog: mergedCatalog)
        commitLayout(
            AIAgentSkillLayout(
                enabledIDs: current.enabledIDs.filter { $0 != id },
                confirmedShortcutIDs: current.confirmedShortcutIDs
            )
        )
    }

    /// Marks the companion Shortcut as added, then tries to occupy a slot.
    @discardableResult
    public func confirmShortcutAndEnable(_ id: String) -> AIAgentSkillEnableResult {
        guard let skill = AIClipboardSkillCatalog.skill(id: id, userCatalog: userCatalog),
              skill.requiresShortcut else {
            return .unknown
        }
        var current = layout.sanitized(catalog: mergedCatalog)
        if !current.confirmedShortcutIDs.contains(id) {
            current.confirmedShortcutIDs.append(id)
        }
        commitLayout(current)
        return enable(id)
    }

    public func moveEnabled(id draggedID: String, onto targetID: String) {
        let ids = layout.sanitized(catalog: mergedCatalog).enabledIDs
        guard let to = ids.firstIndex(of: targetID) else { return }
        moveEnabled(id: draggedID, toIndex: to)
    }

    public func moveEnabled(id draggedID: String, toIndex: Int) {
        var ids = layout.sanitized(catalog: mergedCatalog).enabledIDs
        guard let from = ids.firstIndex(of: draggedID), !ids.isEmpty else { return }
        let to = min(max(toIndex, 0), ids.count - 1)
        guard from != to else { return }
        ids.move(
            fromOffsets: IndexSet(integer: from),
            toOffset: to > from ? to + 1 : to
        )
        commitLayout(
            AIAgentSkillLayout(
                enabledIDs: ids,
                confirmedShortcutIDs: layout.confirmedShortcutIDs
            )
        )
    }

    public func saveUserSkill(_ skill: AIUserSkill) throws {
        let previousSkill = userCatalog.skill(id: skill.id)
        let previousURL = previousSkill?.shortcutICloudURL
        let previousLayout = layout.sanitized(catalog: mergedCatalog)
        var catalog = userCatalog
        try catalog.upsert(skill)
        commitUserCatalog(catalog)
        guard previousSkill != nil, previousURL != skill.shortcutICloudURL else {
            return
        }
        let keepsKeyboardSlot = skill.shortcutICloudURL == nil
        commitLayout(
            AIAgentSkillLayout(
                enabledIDs: keepsKeyboardSlot
                    ? previousLayout.enabledIDs
                    : previousLayout.enabledIDs.filter { $0 != skill.id },
                confirmedShortcutIDs: previousLayout.confirmedShortcutIDs.filter {
                    $0 != skill.id
                }
            )
        )
    }

    public func deleteUserSkill(id: String) {
        var catalog = userCatalog
        catalog.remove(id: id)
        commitUserCatalog(catalog)
        let current = layout.sanitized(catalog: mergedCatalog)
        commitLayout(
            AIAgentSkillLayout(
                enabledIDs: current.enabledIDs.filter { $0 != id },
                confirmedShortcutIDs: current.confirmedShortcutIDs.filter { $0 != id }
            )
        )
    }

    private func commitLayout(_ layout: AIAgentSkillLayout) {
        persistLayout(layout)
        self.layout = loadLayout()
    }

    private func commitUserCatalog(_ catalog: AIUserSkillCatalog) {
        persistUserCatalog(catalog)
        userCatalog = loadUserCatalog()
        layout = loadLayout()
    }
}
