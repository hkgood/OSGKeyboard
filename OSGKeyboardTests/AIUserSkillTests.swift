// AIUserSkillTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class AIUserSkillTests: XCTestCase {
    private let sampleURL = URL(
        string: "https://www.icloud.com/shortcuts/65bf33ba4206484ba78d582eaf1e9c44"
    )!

    func testValidICloudShareLink() {
        XCTAssertNotNil(AIShortcutShareLink.parse(
            "https://www.icloud.com/shortcuts/65bf33ba4206484ba78d582eaf1e9c44"
        ))
        XCTAssertNotNil(AIShortcutShareLink.parse(
            "https://icloud.com/shortcuts/1f4afcf7ee22400cbf84e319d969aadf"
        ))
        XCTAssertNil(AIShortcutShareLink.parse("https://example.com/shortcuts/abc"))
        XCTAssertNil(AIShortcutShareLink.parse("https://www.icloud.com/shortcuts/api/records/x"))
        XCTAssertNil(AIShortcutShareLink.parse("not a url"))
        XCTAssertNil(AIShortcutShareLink.parse("https://www.icloud.com/shortcuts/short"))
    }

    func testParsesShortcutNameFromRecordsJSON() throws {
        let json = """
        {"fields":{"name":{"type":"STRING","value":"OSG · 提取待办"}}}
        """.data(using: .utf8)!
        XCTAssertEqual(try AIShortcutShareMetadata.name(fromRecordsJSON: json), "OSG · 提取待办")
    }

    func testParsesShortcutNameFromLegacyRecordsArray() throws {
        let json = """
        {"records":[{"fields":{"name":{"value":"OSG · 提取日程"}}}]}
        """.data(using: .utf8)!
        XCTAssertEqual(try AIShortcutShareMetadata.name(fromRecordsJSON: json), "OSG · 提取日程")
    }

    func testRejectsRecordsJSONWithoutName() {
        let json = Data(#"{"fields":{}}"#.utf8)
        XCTAssertThrowsError(try AIShortcutShareMetadata.name(fromRecordsJSON: json))
    }

    func testCatalogUpsertKeepsShortcutNameIndependentOfSkillName() throws {
        var catalog = AIUserSkillCatalog()
        var skill = AIUserSkill(
            name: "会议纪要",
            summary: "抽要点",
            prompt: "提取要点",
            shortcutICloudURL: sampleURL,
            shortcutName: "OSG · 提取待办"
        )
        try catalog.upsert(skill)
        XCTAssertEqual(catalog.entries.first?.name, "会议纪要")
        XCTAssertEqual(catalog.entries.first?.shortcutName, "OSG · 提取待办")

        skill.name = "纪要"
        skill.shortcutName = "My Tasks"
        try catalog.upsert(skill)
        XCTAssertEqual(catalog.entries.count, 1)
        XCTAssertEqual(catalog.entries.first?.name, "纪要")
        XCTAssertEqual(catalog.entries.first?.shortcutName, "My Tasks")
    }

    func testTextOnlySkillAllowsEmptyShortcutConfiguration() throws {
        var catalog = AIUserSkillCatalog()
        let skill = AIUserSkill(
            name: "Rewrite",
            prompt: "Rewrite the clipboard"
        )

        try catalog.upsert(skill)

        let saved = try XCTUnwrap(catalog.entries.first)
        let clipboardSkill = saved.asClipboardSkill()
        XCTAssertNil(saved.shortcutICloudURL)
        XCTAssertEqual(saved.shortcutName, "")
        XCTAssertEqual(clipboardSkill.kind, .transform)
        XCTAssertFalse(clipboardSkill.requiresShortcut)
        XCTAssertNil(clipboardSkill.shortcutName)
    }

    func testShortcutNameWithoutLinkDoesNotExport() throws {
        var catalog = AIUserSkillCatalog()
        let skill = AIUserSkill(
            name: "Rewrite",
            prompt: "Rewrite the clipboard",
            shortcutName: "Ignored without a link"
        )

        try catalog.upsert(skill)

        let saved = try XCTUnwrap(catalog.entries.first)
        XCTAssertEqual(saved.shortcutName, "Ignored without a link")
        XCTAssertEqual(saved.asClipboardSkill().kind, .transform)
        XCTAssertNil(saved.asClipboardSkill().shortcutName)
    }

    func testShortcutSkillRequiresNameAndValidShareLink() {
        var catalog = AIUserSkillCatalog()
        XCTAssertThrowsError(
            try catalog.upsert(
                AIUserSkill(
                    name: "Export",
                    prompt: "Export it",
                    shortcutICloudURL: sampleURL
                )
            )
        ) { error in
            XCTAssertEqual(error as? AIUserSkillValidationError, .emptyShortcutName)
        }

        XCTAssertThrowsError(
            try catalog.upsert(
                AIUserSkill(
                    name: "Export",
                    prompt: "Export it",
                    shortcutICloudURL: URL(string: "https://example.com/not-a-shortcut"),
                    shortcutName: "Run Me"
                )
            )
        ) { error in
            XCTAssertEqual(error as? AIUserSkillValidationError, .invalidShortcutLink)
        }
    }

    func testExistingShortcutSkillEncodingDecodesWithOptionalURL() throws {
        let original = AIUserSkill(
            name: "Export",
            prompt: "Export it",
            shortcutICloudURL: sampleURL,
            shortcutName: "Run Me"
        )

        let decoded = try JSONDecoder().decode(
            AIUserSkill.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.shortcutICloudURL, sampleURL)
        XCTAssertEqual(decoded.asClipboardSkill().kind, .export)
        XCTAssertTrue(decoded.asClipboardSkill().requiresShortcut)
    }

    func testThinkingDefaultsOffAndBuiltinCannotEnable() {
        let user = AIUserSkill(
            name: "Custom",
            prompt: "Do it",
            shortcutICloudURL: sampleURL,
            shortcutName: "Run Me"
        )
        XCTAssertFalse(user.thinkingEnabled)
        XCTAssertFalse(user.asClipboardSkill().thinkingEnabled)

        let withThinking = AIUserSkill(
            name: "Custom",
            prompt: "Do it",
            shortcutICloudURL: sampleURL,
            shortcutName: "Run Me",
            thinkingEnabled: true
        )
        XCTAssertTrue(withThinking.asClipboardSkill().thinkingEnabled)

        let builtin = AIClipboardSkillCatalog.skill(id: AIClipboardSkillCatalog.replyID)
        XCTAssertEqual(builtin?.thinkingEnabled, false)
    }

    func testInstructionUsesCustomPrompt() {
        let skill = AIUserSkill(
            name: "Custom",
            prompt: "只输出一行标题",
            shortcutICloudURL: sampleURL,
            shortcutName: "Run Me"
        ).asClipboardSkill()
        XCTAssertEqual(
            AIClipboardSkillCatalog.instruction(
                for: skill,
                locale: "zh",
                translationTargetLocaleId: TranslationLanguageCatalog.offLocaleId
            ),
            "只输出一行标题"
        )
    }

    func testVisibleIncludesUserSkills() throws {
        var catalog = AIUserSkillCatalog()
        let skill = AIUserSkill(
            name: "Custom",
            prompt: "Do it",
            shortcutICloudURL: sampleURL,
            shortcutName: "Run Me"
        )
        try catalog.upsert(skill)
        let visible = AIClipboardSkillCatalog.visible(
            enabledIDs: [skill.id],
            userCatalog: catalog
        )
        XCTAssertEqual(visible.map(\.id), [skill.id])
        XCTAssertEqual(visible.first?.customName, "Custom")
    }

    func testSanitizeKeepsConfirmedUserExportSkill() throws {
        var catalog = AIUserSkillCatalog()
        let skill = AIUserSkill(
            name: "Custom",
            prompt: "Do it",
            shortcutICloudURL: sampleURL,
            shortcutName: "Run Me"
        )
        try catalog.upsert(skill)
        let layout = AIAgentSkillLayout(
            enabledIDs: [skill.id],
            confirmedShortcutIDs: [skill.id]
        ).sanitized(catalog: AIClipboardSkillCatalog.all(userCatalog: catalog))
        XCTAssertEqual(layout.enabledIDs, [skill.id])
    }

    func testGenericExportSplitsLinesAndHonorsNONE() {
        XCTAssertEqual(AIGenericSkillExport.items(from: "NONE"), [])
        XCTAssertEqual(AIGenericSkillExport.items(from: "买牛奶\n回邮件"), ["买牛奶", "回邮件"])
        XCTAssertEqual(AIGenericSkillExport.items(from: "一段没有换行的结果"), ["一段没有换行的结果"])
    }

    func testNoUserSkillLimit() throws {
        var catalog = AIUserSkillCatalog()
        for index in 0..<12 {
            try catalog.upsert(
                AIUserSkill(
                    name: "Skill \(index)",
                    prompt: "Do it",
                    shortcutICloudURL: sampleURL,
                    shortcutName: "Run \(index)"
                )
            )
        }
        XCTAssertEqual(catalog.entries.count, 12)
    }
}
