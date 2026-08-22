// AIAgentSkillLayoutTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class AIAgentSkillLayoutTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.skills.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFreshInstallEnablesEveryBuiltInDefaultSkill() {
        let defaults = makeDefaults()
        let layout = AppGroupStore(defaults: defaults).agentSkillLayout
        XCTAssertEqual(layout.enabledIDs, AIAgentSkillLayout.defaultEnabledIDs)
        XCTAssertEqual(layout.enabledIDs, AIClipboardSkillCatalog.catalog.map(\.id))
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

    func testLegacyLayoutAppendsNewDefaultSkillsWithoutRestoringDisabledLegacySkill() throws {
        let defaults = makeDefaults()
        let legacy = AIAgentSkillLayout(
            enabledIDs: [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID
            ],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(legacy),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(
            Array(migrated.enabledIDs.prefix(2)),
            [AIClipboardSkillCatalog.replyID, AIClipboardSkillCatalog.translateID]
        )
        XCTAssertFalse(migrated.enabledIDs.contains(AIClipboardSkillCatalog.summarizeID))
        XCTAssertTrue(migrated.enabledIDs.contains(AIClipboardSkillCatalog.acceptInvitationID))
        XCTAssertTrue(migrated.enabledIDs.contains(AIClipboardSkillCatalog.extractEventsID))
    }

    func testCannotEnableExportSkillBeforeShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.extractTodosID)
        XCTAssertEqual(
            store.enable(AIClipboardSkillCatalog.extractTodosID),
            .needsShortcut
        )
        XCTAssertFalse(store.layout.isEnabled(AIClipboardSkillCatalog.extractTodosID))
    }

    func testConfirmShortcutAutoEnablesWhenSlotAvailable() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.extractTodosID)
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

    func testSanitizedKeepsUnconfirmedDefaultExportAndDropsUnknownIDs() {
        let layout = AIAgentSkillLayout(
            enabledIDs: ["reply", "extractTodos", "unknown"],
            confirmedShortcutIDs: []
        ).sanitized()
        XCTAssertEqual(layout.enabledIDs, ["reply", "extractTodos"])
    }

    func testSanitizedKeepsConfirmedExport() {
        let layout = AIAgentSkillLayout(
            enabledIDs: ["reply", "extractTodos"],
            confirmedShortcutIDs: ["extractTodos"]
        ).sanitized()
        XCTAssertEqual(layout.enabledIDs, ["reply", "extractTodos"])
    }

    func testSanitizedDoesNotCapEnabledSkillCount() {
        let catalog = (0..<20).map { index in
            AIClipboardSkill(
                id: "skill-\(index)",
                systemImage: "sparkles",
                titleKey: "title",
                cardTitleKey: "title",
                descriptionKey: "description",
                kind: .transform,
                isDefault: true
            )
        }
        let layout = AIAgentSkillLayout(
            enabledIDs: catalog.map(\.id),
            confirmedShortcutIDs: []
        ).sanitized(catalog: catalog)
        XCTAssertEqual(layout.enabledIDs.count, 20)
    }

    func testDisableKeepsShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.extractTodosID)
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
                AIClipboardSkillCatalog.replyInSourceLanguageID
            ] + Array(AIAgentSkillLayout.defaultEnabledIDs.dropFirst(3))
        )
    }

    func testReorderMovesEnabledSkillToIndex() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.moveEnabled(id: AIClipboardSkillCatalog.summarizeID, toIndex: 2)
        XCTAssertEqual(
            Array(store.layout.enabledIDs.prefix(3)),
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.replyInSourceLanguageID,
                AIClipboardSkillCatalog.summarizeID
            ]
        )
        store.moveEnabled(id: AIClipboardSkillCatalog.summarizeID, toIndex: 0)
        XCTAssertEqual(
            Array(store.layout.enabledIDs.prefix(3)),
            [
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.replyInSourceLanguageID
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
        XCTAssertTrue(skill?.isDefault ?? false)
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
        XCTAssertTrue(skill?.isDefault ?? false)
        XCTAssertEqual(skill?.kind, .export)
        XCTAssertFalse(skill?.requiresShortcut ?? true)
    }

    func testNavigateEnablesWithoutShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.navigateID)
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
        XCTAssertTrue(skill?.isDefault ?? false)
        XCTAssertTrue(skill?.requiresShortcut ?? false)
    }

    func testCannotEnableSaveToNotesBeforeShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.saveToNotesID)
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
