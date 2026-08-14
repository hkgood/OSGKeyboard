// AIUserSkillStoreTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class AIUserSkillStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.userSkills.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testChangingShortcutLinkDropsConfirmation() throws {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        let firstURL = URL(string: "https://www.icloud.com/shortcuts/65bf33ba4206484ba78d582eaf1e9c44")!
        let secondURL = URL(string: "https://www.icloud.com/shortcuts/1f4afcf7ee22400cbf84e319d969aadf")!
        var skill = AIUserSkill(
            name: "Custom",
            prompt: "Do it",
            shortcutICloudURL: firstURL,
            shortcutName: "One"
        )
        try store.saveUserSkill(skill)
        XCTAssertEqual(store.confirmShortcutAndEnable(skill.id), .enabled)
        XCTAssertTrue(store.layout.isEnabled(skill.id))

        skill.shortcutICloudURL = secondURL
        skill.shortcutName = "Two"
        try store.saveUserSkill(skill)
        XCTAssertFalse(store.layout.hasConfirmedShortcut(skill.id))
        XCTAssertFalse(store.layout.isEnabled(skill.id))
    }

    func testRemovingShortcutLinkKeepsEnabledTextSkill() throws {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        var skill = AIUserSkill(
            name: "Custom",
            prompt: "Do it",
            shortcutICloudURL: URL(
                string: "https://www.icloud.com/shortcuts/65bf33ba4206484ba78d582eaf1e9c44"
            ),
            shortcutName: "Run Me"
        )
        try store.saveUserSkill(skill)
        XCTAssertEqual(store.confirmShortcutAndEnable(skill.id), .enabled)

        skill.shortcutICloudURL = nil
        try store.saveUserSkill(skill)

        XCTAssertTrue(store.layout.isEnabled(skill.id))
        XCTAssertFalse(store.layout.hasConfirmedShortcut(skill.id))
        XCTAssertEqual(store.userSkill(id: skill.id)?.asClipboardSkill().kind, .transform)
    }

    func testAddingShortcutLinkDisablesTextSkillUntilConfirmed() throws {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        var skill = AIUserSkill(
            name: "Custom",
            prompt: "Do it"
        )
        try store.saveUserSkill(skill)
        XCTAssertEqual(store.enable(skill.id), .enabled)

        skill.shortcutICloudURL = URL(
            string: "https://www.icloud.com/shortcuts/65bf33ba4206484ba78d582eaf1e9c44"
        )
        skill.shortcutName = "Run Me"
        try store.saveUserSkill(skill)

        XCTAssertFalse(store.layout.isEnabled(skill.id))
        XCTAssertFalse(store.layout.hasConfirmedShortcut(skill.id))
        XCTAssertEqual(store.enable(skill.id), .needsShortcut)
    }
}
