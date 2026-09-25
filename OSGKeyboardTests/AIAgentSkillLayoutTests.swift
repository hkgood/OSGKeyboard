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
        XCTAssertEqual(
            layout.enabledIDs,
            AIClipboardSkillCatalog.catalog.filter(\.isDefault).map(\.id)
        )
        // "Speak as me" is included: it has no toggle of its own, and the
        // personal-style gate keeps it off the keyboard until one is distilled.
        XCTAssertTrue(layout.enabledIDs.contains(AIClipboardSkillCatalog.speakAsMeID))
        XCTAssertTrue(layout.confirmedShortcutIDs.isEmpty)
    }

    /// The skill has no switch of its own. It ships enabled, and distilling a
    /// personal style is the single act that makes it reachable.
    func testSpeakAsMeShipsEnabledAndIsGatedOnlyByThePersonalStyle() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        XCTAssertTrue(store.layout.isEnabled(AIClipboardSkillCatalog.speakAsMeID))

        XCTAssertFalse(
            AIClipboardSkillCatalog.availableEnabledIDs(
                store.layout.enabledIDs,
                layout: store.layout,
                hasPersonalReplyStyle: false
            ).contains(AIClipboardSkillCatalog.speakAsMeID)
        )
        XCTAssertTrue(
            AIClipboardSkillCatalog.availableEnabledIDs(
                store.layout.enabledIDs,
                layout: store.layout,
                hasPersonalReplyStyle: true
            ).contains(AIClipboardSkillCatalog.speakAsMeID)
        )
    }

    func testSystemSemanticSkillsStayEnabledButHiddenFromSkillManagement() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        let hiddenIDs = AIClipboardSkillCatalog.hiddenFromSkillManagementIDs

        // "Hidden" means system action: always enabled, never user-managed.
        XCTAssertTrue(hiddenIDs.isSubset(of: Set(store.enabledSkills.map(\.id))))
        // The lists additionally omit skills managed from elsewhere in the UI,
        // which are not necessarily enabled.
        let omittedIDs = AIClipboardSkillCatalog.managedOutsideSkillListIDs
        XCTAssertTrue(hiddenIDs.isSubset(of: omittedIDs))
        XCTAssertTrue(
            omittedIDs.isDisjoint(with: Set(store.skillManagementEnabledSkills.map(\.id)))
        )
        XCTAssertTrue(
            omittedIDs.isDisjoint(with: Set(store.skillManagementAvailableSkills.map(\.id)))
        )
        XCTAssertTrue(
            store.skillManagementEnabledSkills.contains {
                $0.id == AIClipboardSkillCatalog.translateID
            }
        )

        store.disable(AIClipboardSkillCatalog.replyID)

        XCTAssertFalse(
            store.skillManagementAvailableSkills.contains {
                $0.id == AIClipboardSkillCatalog.replyID
            }
        )
        XCTAssertTrue(
            store.mergedCatalog.contains {
                $0.id == AIClipboardSkillCatalog.replyID
            }
        )
    }

    func testEmptyEnabledListIsPreserved() {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        store.setAgentSkillLayout(
            AIAgentSkillLayout(enabledIDs: [], confirmedShortcutIDs: [])
        )
        XCTAssertEqual(store.agentSkillLayout.enabledIDs, [])
    }

    func testLegacyLayoutInstallsCurrentRequiredDefaultSkills() throws {
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
        XCTAssertTrue(migrated.enabledIDs.contains(AIClipboardSkillCatalog.summarizeID))
        XCTAssertTrue(migrated.enabledIDs.contains(AIClipboardSkillCatalog.replyID))
        XCTAssertTrue(migrated.enabledIDs.contains(AIClipboardSkillCatalog.extractEventsID))
    }

    func testVersionOneLayoutAddsLaterBuiltInDefaults() throws {
        let defaults = makeDefaults()
        let layout = AIAgentSkillLayout(
            enabledIDs: [AIClipboardSkillCatalog.replyID],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(layout),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            1,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(
            migrated.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.openLinkID,
                AIClipboardSkillCatalog.summarizeWebPageID,
                AIClipboardSkillCatalog.callPhoneID,
                AIClipboardSkillCatalog.createContactID,
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.organizeListID
            ]
        )
    }

    func testVersionThreeLayoutAddsLinkAndPhoneSkills() throws {
        let defaults = makeDefaults()
        let layout = AIAgentSkillLayout(
            enabledIDs: [AIClipboardSkillCatalog.replyID],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(layout),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            3,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(
            migrated.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.openLinkID,
                AIClipboardSkillCatalog.summarizeWebPageID,
                AIClipboardSkillCatalog.callPhoneID,
                AIClipboardSkillCatalog.createContactID,
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.organizeListID
            ]
        )
    }

    func testVersionFourLayoutAddsPhoneSkills() throws {
        let defaults = makeDefaults()
        let layout = AIAgentSkillLayout(
            enabledIDs: [AIClipboardSkillCatalog.replyID],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(layout),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            4,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(
            migrated.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.callPhoneID,
                AIClipboardSkillCatalog.createContactID,
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.organizeListID
            ]
        )
    }

    func testVersionFiveLayoutConsolidatesLegacySkillIDs() throws {
        let defaults = makeDefaults()
        let layout = AIAgentSkillLayout(
            enabledIDs: [
                AIClipboardSkillCatalog.replyInSourceLanguageID,
                AIClipboardSkillCatalog.extractConclusionsID,
                AIClipboardSkillCatalog.askForDetailsID
            ],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(layout),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            5,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(
            migrated.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.organizeListID
            ]
        )
        XCTAssertEqual(
            defaults.integer(
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            ),
            11
        )
    }

    func testVersionSixLayoutInstallsRequiredDefaultsOnlyOnce() throws {
        let defaults = makeDefaults()
        let initial = AIAgentSkillLayout(
            enabledIDs: [AIClipboardSkillCatalog.playfulReplyID],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(initial),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            6,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(
            store.agentSkillLayout.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.translateID,
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.organizeListID
            ]
        )

        store.setAgentSkillLayout(
            AIAgentSkillLayout(
                enabledIDs: store.agentSkillLayout.enabledIDs.filter {
                    $0 != AIClipboardSkillCatalog.replyID
                },
                confirmedShortcutIDs: []
            )
        )

        XCTAssertFalse(store.agentSkillLayout.isEnabled(AIClipboardSkillCatalog.replyID))
    }

    func testVersionEightLayoutConsolidatesLegacyReplyIDsAndPersistsMigration() throws {
        let defaults = makeDefaults()
        let initial = AIAgentSkillLayout(
            enabledIDs: [AIClipboardSkillCatalog.playfulReplyID],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(initial),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            8,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(migrated.enabledIDs, [AIClipboardSkillCatalog.replyID])
        XCTAssertEqual(
            defaults.integer(
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            ),
            11
        )
    }

    func testVersionEightMigrationDoesNotRestoreDisabledReply() throws {
        let defaults = makeDefaults()
        let initial = AIAgentSkillLayout(
            enabledIDs: [AIClipboardSkillCatalog.translateID],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(initial),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            8,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let store = AppGroupStore(defaults: defaults)

        XCTAssertEqual(store.agentSkillLayout.enabledIDs, [AIClipboardSkillCatalog.translateID])
        XCTAssertEqual(
            defaults.integer(
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            ),
            11
        )
        XCTAssertEqual(
            AppGroupStore(defaults: defaults).agentSkillLayout.enabledIDs,
            [AIClipboardSkillCatalog.translateID]
        )
    }

    func testVersionNineLayoutConsolidatesEmpathyReplyAndPersistsMigration() throws {
        let defaults = makeDefaults()
        let initial = AIAgentSkillLayout(
            enabledIDs: [
                AIClipboardSkillCatalog.empathyReplyID,
                AIClipboardSkillCatalog.translateID
            ],
            confirmedShortcutIDs: []
        )
        defaults.set(
            try JSONEncoder().encode(initial),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        defaults.set(
            9,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        let migrated = AppGroupStore(defaults: defaults).agentSkillLayout

        XCTAssertEqual(
            migrated.enabledIDs,
            [AIClipboardSkillCatalog.replyID, AIClipboardSkillCatalog.translateID]
        )
        XCTAssertEqual(
            defaults.integer(
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            ),
            11
        )
    }

    func testVersionTenLayoutConsolidatesDecisionRepliesWithoutRestoringDisabledReply() throws {
        let enabledDefaults = makeDefaults()
        let legacy = AIAgentSkillLayout(
            enabledIDs: [
                AIClipboardSkillCatalog.acceptInvitationID,
                AIClipboardSkillCatalog.declineInvitationID,
                AIClipboardSkillCatalog.acceptTaskID,
                AIClipboardSkillCatalog.clarifyRequestID,
                AIClipboardSkillCatalog.blessingReplyID
            ],
            confirmedShortcutIDs: []
        )
        enabledDefaults.set(
            try JSONEncoder().encode(legacy),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        enabledDefaults.set(
            10,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )

        XCTAssertEqual(
            AppGroupStore(defaults: enabledDefaults).agentSkillLayout.enabledIDs,
            [AIClipboardSkillCatalog.replyID]
        )

        let disabledDefaults = makeDefaults()
        disabledDefaults.set(
            try JSONEncoder().encode(
                AIAgentSkillLayout(
                    enabledIDs: [AIClipboardSkillCatalog.translateID],
                    confirmedShortcutIDs: []
                )
            ),
            forKey: AppGroupConfiguration.Keys.agentSkillLayout
        )
        disabledDefaults.set(
            10,
            forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
        )
        XCTAssertEqual(
            AppGroupStore(defaults: disabledDefaults).agentSkillLayout.enabledIDs,
            [AIClipboardSkillCatalog.translateID]
        )
    }

    func testLegacyReplyLookupRemainsAvailableButCanonicalizesForLayout() {
        XCTAssertNotNil(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.playfulReplyID)
        )
        XCTAssertNotNil(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.businessReplyID)
        )
        XCTAssertNotNil(
            AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.empathyReplyID)
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.canonicalID(for: AIClipboardSkillCatalog.playfulReplyID),
            AIClipboardSkillCatalog.replyID
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.canonicalID(for: AIClipboardSkillCatalog.businessReplyID),
            AIClipboardSkillCatalog.replyID
        )
        XCTAssertEqual(
            AIClipboardSkillCatalog.canonicalID(for: AIClipboardSkillCatalog.empathyReplyID),
            AIClipboardSkillCatalog.replyID
        )
        for id in [
            AIClipboardSkillCatalog.acceptInvitationID,
            AIClipboardSkillCatalog.declineInvitationID,
            AIClipboardSkillCatalog.acceptTaskID,
            AIClipboardSkillCatalog.clarifyRequestID,
            AIClipboardSkillCatalog.blessingReplyID,
            AIClipboardSkillCatalog.askForDetailsID
        ] {
            XCTAssertEqual(
                AIClipboardSkillCatalog.canonicalID(for: id),
                AIClipboardSkillCatalog.replyID
            )
            XCTAssertEqual(
                AIClipboardSkillCatalog.skill(id: id)?.id,
                AIClipboardSkillCatalog.replyID
            )
        }
        XCTAssertFalse(
            AIClipboardSkillCatalog.catalog.contains {
                $0.id == AIClipboardSkillCatalog.playfulReplyID
                    || $0.id == AIClipboardSkillCatalog.businessReplyID
                    || $0.id == AIClipboardSkillCatalog.empathyReplyID
                    || $0.id == AIClipboardSkillCatalog.acceptInvitationID
                    || $0.id == AIClipboardSkillCatalog.declineInvitationID
                    || $0.id == AIClipboardSkillCatalog.acceptTaskID
                    || $0.id == AIClipboardSkillCatalog.clarifyRequestID
                    || $0.id == AIClipboardSkillCatalog.blessingReplyID
            }
        )
    }

    func testCannotEnableExportSkillBeforeShortcutConfirmation() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.saveToNotesID)
        XCTAssertEqual(
            store.enable(AIClipboardSkillCatalog.saveToNotesID),
            .needsShortcut
        )
        XCTAssertFalse(store.layout.isEnabled(AIClipboardSkillCatalog.saveToNotesID))
    }

    func testConfirmShortcutAutoEnablesWhenSlotAvailable() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.disable(AIClipboardSkillCatalog.saveToNotesID)
        XCTAssertEqual(
            store.confirmShortcutAndEnable(AIClipboardSkillCatalog.saveToNotesID),
            .enabled
        )
        XCTAssertTrue(store.layout.hasConfirmedShortcut(AIClipboardSkillCatalog.saveToNotesID))
        XCTAssertEqual(
            store.layout.enabledIDs.last,
            AIClipboardSkillCatalog.saveToNotesID
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

    func testSanitizedConsolidatesLegacySkillIDsWithoutDuplicates() {
        let layout = AIAgentSkillLayout(
            enabledIDs: [
                AIClipboardSkillCatalog.replyInSourceLanguageID,
                AIClipboardSkillCatalog.playfulReplyID,
                AIClipboardSkillCatalog.businessReplyID,
                AIClipboardSkillCatalog.empathyReplyID,
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.extractConclusionsID,
                AIClipboardSkillCatalog.askForDetailsID
            ],
            confirmedShortcutIDs: []
        ).sanitized()

        XCTAssertEqual(
            layout.enabledIDs,
            [
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.summarizeID
            ]
        )
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
        store.disable(AIClipboardSkillCatalog.saveToNotesID)
        _ = store.confirmShortcutAndEnable(AIClipboardSkillCatalog.saveToNotesID)
        store.disable(AIClipboardSkillCatalog.saveToNotesID)
        XCTAssertFalse(store.layout.isEnabled(AIClipboardSkillCatalog.saveToNotesID))
        XCTAssertTrue(store.layout.hasConfirmedShortcut(AIClipboardSkillCatalog.saveToNotesID))
        XCTAssertEqual(store.enable(AIClipboardSkillCatalog.saveToNotesID), .enabled)
    }

    func testReorderMovesEnabledSkill() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        store.moveEnabled(
            id: AIClipboardSkillCatalog.translateID,
            onto: AIClipboardSkillCatalog.replyID
        )
        var expected = AIAgentSkillLayout.defaultEnabledIDs
        expected.removeAll { $0 == AIClipboardSkillCatalog.translateID }
        expected.insert(AIClipboardSkillCatalog.translateID, at: 0)
        XCTAssertEqual(
            store.layout.enabledIDs,
            expected
        )
    }

    func testReorderMovesEnabledSkillToIndex() {
        let store = AIAgentSkillLayoutStore(defaults: makeDefaults())
        // Derived from the default order rather than hardcoded: this asserts
        // the move, not which skills happen to lead the catalog.
        var others = AIAgentSkillLayout.defaultEnabledIDs
        others.removeAll { $0 == AIClipboardSkillCatalog.summarizeID }
        let leading = Array(others.prefix(2))

        store.moveEnabled(id: AIClipboardSkillCatalog.summarizeID, toIndex: 2)
        XCTAssertEqual(
            Array(store.layout.enabledIDs.prefix(3)),
            leading + [AIClipboardSkillCatalog.summarizeID]
        )
        store.moveEnabled(id: AIClipboardSkillCatalog.summarizeID, toIndex: 0)
        XCTAssertEqual(
            Array(store.layout.enabledIDs.prefix(3)),
            [AIClipboardSkillCatalog.summarizeID] + leading
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

    func testPendingContactCreationIsNormalizedAndConsumedOnce() {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)

        store.setPendingContactCreation(phoneNumber: "+1 (408) 996-1010")

        XCTAssertEqual(
            store.consumePendingContactCreation()?.phoneNumber,
            "+14089961010"
        )
        XCTAssertNil(store.consumePendingContactCreation())
    }

    func testPendingContactCreationExpires() throws {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        let now = Date()
        let payload = AIContactCreationPayload(
            phoneNumber: "400-666-8800",
            createdAt: now.addingTimeInterval(
                -AIContactCreationHandoff.maximumAge - 1
            )
        )
        defaults.set(
            try XCTUnwrap(AIContactCreationHandoff.encode(payload)),
            forKey: AIContactCreationHandoff.pendingKey
        )

        XCTAssertNil(store.consumePendingContactCreation(now: now))
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
        let shortcutName = AIClipboardSkillCatalog.saveToNotesShortcutName
        let url = AIAgentShortcutRun.shortcutsRunURL(name: shortcutName, text: "买牛奶\n回邮件")
        XCTAssertEqual(url?.scheme, "shortcuts")
        XCTAssertEqual(url?.host, "run-shortcut")
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "name" }?.value, "OSGSaveToNotes")
        XCTAssertEqual(items.first { $0.name == "input" }?.value, "text")
        XCTAssertEqual(items.first { $0.name == "text" }?.value, "买牛奶\n回邮件")
        XCTAssertNil(items.first { $0.name == "x-success" })
    }

    func testXCallbackRunURLUsesCallbackHost() {
        let url = AIAgentShortcutRun.shortcutsRunURL(
            name: AIClipboardSkillCatalog.saveToNotesShortcutName,
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

    func testExtractTodosIsNativeWithoutShortcut() {
        // Reminders are created natively via EventKit in the host, so this
        // built-in skill must not carry any companion Shortcut metadata.
        let skill = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.extractTodosID)
        XCTAssertNil(skill?.shortcutICloudURL)
        XCTAssertNil(skill?.shortcutName)
        XCTAssertNil(skill?.shortcutResourceName)
        XCTAssertFalse(skill?.requiresShortcut ?? true)
        XCTAssertEqual(skill?.kind, .export)
    }

    func testExtractEventsIsNativeWithoutShortcut() {
        // Calendar events are created natively via EventKit in the host, so this
        // built-in skill must not carry any companion Shortcut metadata.
        let skill = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.extractEventsID)
        XCTAssertNil(skill?.shortcutICloudURL)
        XCTAssertNil(skill?.shortcutName)
        XCTAssertNil(skill?.shortcutResourceName)
        XCTAssertFalse(skill?.requiresShortcut ?? true)
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
