// AIAgentSkillLayoutTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

@MainActor
final class AIAgentSkillLayoutTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.skills.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFreshInstallEnablesDefaultTransformSkills() {
        let defaults = makeDefaults()
        let layout = AppGroupStore(defaults: defaults).agentSkillLayout
        XCTAssertEqual(layout.enabledIDs, AIAgentSkillLayout.defaultEnabledIDs)
        XCTAssertTrue(layout.confirmedShortcutIDs.isEmpty)
    }

    func testEmptyEnabledListIsPreserved() {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        store.setAgentSkillLayout(
            AIAgentSkillLayout(enabledIDs: [], confirmedShortcutIDs: [])
        )
        XCTAssertEqual(store.agentSkillLayout.enabledIDs, [])
    }

    func testCannotEnableExportSkillBeforeShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        XCTAssertEqual(
            store.enable(AIClipboardSkillCatalog.extractTodosID),
            .needsShortcut
        )
        XCTAssertFalse(store.layout.isEnabled(AIClipboardSkillCatalog.extractTodosID))
    }

    func testConfirmShortcutAutoEnablesWhenSlotAvailable() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        XCTAssertEqual(
            store.confirmShortcutAndEnable(AIClipboardSkillCatalog.extractTodosID),
            .enabled
        )
        XCTAssertTrue(store.layout.hasConfirmedShortcut(AIClipboardSkillCatalog.extractTodosID))
        XCTAssertEqual(
            store.layout.enabledIDs.last,
            AIClipboardSkillCatalog.extractTodosID
        )
    }

    func testSanitizedDropsUnconfirmedExportAndUnknownIDs() {
        let layout = AIAgentSkillLayout(
            enabledIDs: ["reply", "extractTodos", "unknown"],
            confirmedShortcutIDs: []
        ).sanitized()
        XCTAssertEqual(layout.enabledIDs, ["reply"])
    }

    func testSanitizedKeepsConfirmedExport() {
        let layout = AIAgentSkillLayout(
            enabledIDs: ["reply", "extractTodos"],
            confirmedShortcutIDs: ["extractTodos"]
        ).sanitized()
        XCTAssertEqual(layout.enabledIDs, ["reply", "extractTodos"])
    }

    func testIsFullUsesEnabledCount() {
        let full = AIAgentSkillLayout(
            enabledIDs: (0..<AIAgentSkillLayout.maximumEnabled).map(String.init),
            confirmedShortcutIDs: []
        )
        XCTAssertTrue(full.isFull)
        XCTAssertEqual(AIAgentSkillLayout.maximumEnabled, 8)
    }

    func testDisableKeepsShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        _ = store.confirmShortcutAndEnable(AIClipboardSkillCatalog.extractTodosID)
        store.disable(AIClipboardSkillCatalog.extractTodosID)
        XCTAssertFalse(store.layout.isEnabled(AIClipboardSkillCatalog.extractTodosID))
        XCTAssertTrue(store.layout.hasConfirmedShortcut(AIClipboardSkillCatalog.extractTodosID))
        XCTAssertEqual(store.enable(AIClipboardSkillCatalog.extractTodosID), .enabled)
    }

    func testReorderMovesEnabledSkill() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.moveEnabled(
            id: AIClipboardSkillCatalog.translateID,
            onto: AIClipboardSkillCatalog.replyID
        )
        XCTAssertEqual(
            store.layout.enabledIDs,
            [
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.summarizeID,
            ]
        )
    }

    func testReorderMovesEnabledSkillToIndex() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.moveEnabled(id: AIClipboardSkillCatalog.summarizeID, toIndex: 2)
        XCTAssertEqual(
            store.layout.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.summarizeID,
            ]
        )
        store.moveEnabled(id: AIClipboardSkillCatalog.summarizeID, toIndex: 0)
        XCTAssertEqual(
            store.layout.enabledIDs,
            [
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID,
            ]
        )
    }

    func testVisibleEmptyEnabledIDsShowsNoChips() {
        XCTAssertEqual(AIClipboardSkillCatalog.visible(enabledIDs: []).map(\.id), [])
    }

    func testNONEAndEmptyProduceNoItems() {
        XCTAssertEqual(AITodoExtraction.items(from: "NONE"), [])
        XCTAssertEqual(AITodoExtraction.items(from: "没有待办事项"), [])
        XCTAssertEqual(AITodoExtraction.items(from: "  \n  "), [])
        XCTAssertEqual(AITodoExtraction.items(from: "no tasks"), [])
    }

    func testStripsBulletsAndCapsAtTwenty() {
        let lines = (1...25).map { "- 任务\($0)" }.joined(separator: "\n")
        let items = AITodoExtraction.items(from: lines)
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.first, "任务1")
    }

    func testSingleShortTaskIsKept() {
        XCTAssertEqual(AITodoExtraction.items(from: "买牛奶"), ["买牛奶"])
    }

    func testWholeClipboardEchoIsRejected() {
        let source = String(repeating: "这是一段很长的会议纪要内容，包含许多句子。", count: 4)
        XCTAssertEqual(
            AITodoExtraction.items(from: source, sourceClipboard: source),
            []
        )
    }

    func testPendingShortcutPayloadExpires() {
        let old = AIAgentShortcutRunPayload(
            skillID: "extractTodos",
            titles: ["买牛奶"],
            createdAt: Date(timeIntervalSinceNow: -120)
        )
        let data = AIAgentShortcutRun.encode(old)!
        XCTAssertNil(AIAgentShortcutRun.decode(data))
    }

    func testShortcutsRunURLPreservesNotesFieldSeparator() {
        let text = "周会纪要\(AINoteExport.fieldSeparator)第一项\n第二项"
        let url = AIAgentShortcutRun.shortcutsRunURL(name: "OSGSaveToNotes", text: text)
        let raw = url?.absoluteString ?? ""
        XCTAssertFalse(raw.contains("<"), "angle brackets in the URL get stripped by Shortcuts")
        XCTAssertFalse(raw.contains(">"))
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "text" }?.value, text)
        XCTAssertTrue(text.contains("||OSG_NOTE||"))
    }

    func testShortcutsRunURLIncludesNameAndText() {
        let shortcutName = AIClipboardSkillCatalog.extractTodosShortcutName
        let url = AIAgentShortcutRun.shortcutsRunURL(name: shortcutName, text: "买牛奶\n回邮件")
        XCTAssertEqual(url?.scheme, "shortcuts")
        XCTAssertEqual(url?.host, "run-shortcut")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "OSGExtractTodos")
        XCTAssertEqual(items.first { $0.name == "input" }?.value, "text")
        XCTAssertEqual(items.first { $0.name == "text" }?.value, "买牛奶\n回邮件")
        XCTAssertNil(items.first { $0.name == "x-success" })
    }

    func testXCallbackRunURLUsesCallbackHost() {
        let url = AIAgentShortcutRun.shortcutsRunURL(
            name: AIClipboardSkillCatalog.extractTodosShortcutName,
            text: "买牛奶",
            xSuccess: "osgkeyboard://skill/shortcut-result?status=success",
            xError: "osgkeyboard://skill/shortcut-result?status=error",
            xCancel: "osgkeyboard://skill/shortcut-result?status=cancel"
        )
        XCTAssertEqual(url?.scheme, "shortcuts")
        XCTAssertEqual(url?.host, "x-callback-url")
        XCTAssertEqual(url?.path, "/run-shortcut")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "text" }?.value, "买牛奶")
        XCTAssertEqual(
            items.first { $0.name == "x-success" }?.value,
            "osgkeyboard://skill/shortcut-result?status=success"
        )
    }

    func testPreviewEscapesNewlines() {
        XCTAssertEqual(AIAgentShortcutRun.preview("买牛奶\n回邮件"), "买牛奶\\n回邮件")
    }

    func testExtractTodosUsesBundledShortcut() {
        let skill = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.extractTodosID)
        XCTAssertNil(skill?.shortcutICloudURL)
        XCTAssertEqual(skill?.shortcutName, "OSGExtractTodos")
        XCTAssertEqual(skill?.shortcutResourceName, "OSGExtractTodos")
    }

    func testExtractEventsUsesBundledShortcut() {
        let skill = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.extractEventsID)
        XCTAssertNil(skill?.shortcutICloudURL)
        XCTAssertEqual(skill?.shortcutName, "OSGExtractEvents")
        XCTAssertEqual(
            skill?.shortcutResourceName,
            "OSGExtractEvents"
        )
        XCTAssertEqual(skill?.systemImage, "calendar")
        XCTAssertFalse(skill?.isDefault ?? true)
    }

    func testNavigateDoesNotRequireShortcut() {
        let skill = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.navigateID)
        XCTAssertNil(skill?.shortcutName)
        XCTAssertNil(skill?.shortcutICloudURL)
        XCTAssertNil(skill?.shortcutResourceName)
        XCTAssertEqual(
            skill?.systemImage,
            "arrow.triangle.turn.up.right.diamond.fill"
        )
        XCTAssertFalse(skill?.isDefault ?? true)
        XCTAssertEqual(skill?.kind, .export)
        XCTAssertFalse(skill?.requiresShortcut ?? true)
    }

    func testNavigateEnablesWithoutShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        XCTAssertEqual(
            store.enable(AIClipboardSkillCatalog.navigateID),
            .enabled
        )
        XCTAssertTrue(store.layout.isEnabled(AIClipboardSkillCatalog.navigateID))
    }

    func testSaveToNotesUsesBundledShortcutUntilICloudShareExists() {
        let skill = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.saveToNotesID)
        XCTAssertNil(skill?.shortcutICloudURL)
        XCTAssertEqual(skill?.shortcutName, "OSGSaveToNotes")
        XCTAssertEqual(skill?.shortcutResourceName, "OSGSaveToNotes")
        XCTAssertEqual(skill?.systemImage, "note.text")
        XCTAssertFalse(skill?.isDefault ?? true)
        XCTAssertTrue(skill?.requiresShortcut ?? false)
    }

    func testCannotEnableSaveToNotesBeforeShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        XCTAssertEqual(
            store.enable(AIClipboardSkillCatalog.saveToNotesID),
            .needsShortcut
        )
        XCTAssertFalse(store.layout.isEnabled(AIClipboardSkillCatalog.saveToNotesID))
    }

    func testICloudShareLinkMapsToShortcutsInstallURL() {
        let share = URL(string: "https://www.icloud.com/shortcuts/65bf33ba4206484ba78d582eaf1e9c44")!
        let url = AIAgentShortcutRun.shortcutsInstallURL(from: share)
        XCTAssertEqual(url?.scheme, "shortcuts")
        XCTAssertEqual(url?.host, "shortcuts")
        XCTAssertEqual(url?.path, "/65bf33ba4206484ba78d582eaf1e9c44")
        XCTAssertEqual(
            AIAgentShortcutRun.iCloudShareToken(from: share),
            "65bf33ba4206484ba78d582eaf1e9c44"
        )
    }
}
