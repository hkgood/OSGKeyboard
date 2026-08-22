// OfficialSkillCatalogTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

@MainActor
final class OfficialSkillCatalogTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.officialSkills.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func definition(
        id: String = "official.rewrite",
        systemImage: String = "wand.and.stars",
        sortOrder: Int = 10,
        kind: AIClipboardSkillKind = .transform,
        englishName: String = "Rewrite",
        englishSummary: String = "Rewrite clipboard text clearly",
        englishPrompt: String = "Rewrite the clipboard clearly."
    ) -> OfficialSkillDefinition {
        OfficialSkillDefinition(
            id: id,
            systemImage: systemImage,
            sortOrder: sortOrder,
            kind: kind,
            thinkingEnabled: true,
            localizations: [
                "zh-Hans": OfficialSkillLocalization(
                    name: "改写",
                    summary: "清晰改写剪贴板内容",
                    prompt: "请清晰改写剪贴板内容。"
                ),
                "en": OfficialSkillLocalization(
                    name: englishName,
                    summary: englishSummary,
                    prompt: englishPrompt
                )
            ]
        )
    }

    func testValidatedCatalogSortsAndMapsBothLanguages() throws {
        let catalog = try OfficialSkillCatalog(
            revision: 7,
            generatedAt: "2026-08-21T03:00:00Z",
            skills: [
                definition(id: "official.second", sortOrder: 20),
                definition(id: "official.first", sortOrder: 10)
            ]
        ).validated()

        XCTAssertEqual(catalog.skills.map(\.id), ["official.first", "official.second"])
        XCTAssertEqual(
            catalog.resolvedSkills(language: .chinese).first?.customName,
            "改写"
        )
        XCTAssertEqual(
            catalog.resolvedSkills(language: .english).first?.customPrompt,
            "Rewrite the clipboard clearly."
        )
        XCTAssertTrue(catalog.resolvedSkills(language: .english).first?.thinkingEnabled ?? false)
    }

    func testValidationRejectsWholeInvalidSnapshot() {
        let invalidCases = [
            OfficialSkillCatalog(
                schemaVersion: 2,
                revision: 1,
                skills: [definition()]
            ),
            OfficialSkillCatalog(
                revision: 1,
                skills: [definition(), definition()]
            ),
            OfficialSkillCatalog(
                revision: 1,
                skills: [definition(id: "remote.rewrite")]
            ),
            OfficialSkillCatalog(
                revision: 1,
                skills: [definition(kind: .export)]
            ),
            OfficialSkillCatalog(
                revision: 1,
                skills: [definition(englishPrompt: "   ")]
            ),
            OfficialSkillCatalog(
                revision: 1,
                skills: [
                    definition(
                        englishPrompt: String(
                            repeating: "x",
                            count: OfficialSkillCatalog.maximumPromptCharacters + 1
                        )
                    )
                ]
            )
        ]

        for catalog in invalidCases {
            XCTAssertThrowsError(try catalog.validated())
        }
    }

    func testContractBoundariesAcceptExactMaximums() {
        let prefix = "official."
        let maximumID = prefix + String(
            repeating: "a",
            count: OfficialSkillCatalog.maximumIDCharacters - prefix.count
        )
        let maximumDefinition = definition(
            id: maximumID,
            systemImage: String(
                repeating: "s",
                count: OfficialSkillCatalog.maximumSystemImageCharacters
            ),
            sortOrder: OfficialSkillCatalog.maximumSortOrder,
            englishName: String(
                repeating: "n",
                count: OfficialSkillCatalog.maximumNameCharacters
            ),
            englishSummary: String(
                repeating: "s",
                count: OfficialSkillCatalog.maximumSummaryCharacters
            ),
            englishPrompt: String(
                repeating: "p",
                count: OfficialSkillCatalog.maximumPromptCharacters
            )
        )

        XCTAssertNoThrow(
            try OfficialSkillCatalog(revision: 1, skills: [maximumDefinition]).validated()
        )
        XCTAssertNoThrow(
            try OfficialSkillCatalog(
                revision: 1,
                skills: [definition(sortOrder: 0)]
            ).validated()
        )
    }

    func testContractBoundariesRejectValuesOverLimits() {
        let invalidDefinitions = [
            definition(
                id: "official." + String(
                    repeating: "a",
                    count: OfficialSkillCatalog.maximumIDCharacters + 1
                        - "official.".count
                )
            ),
            definition(
                systemImage: String(
                    repeating: "s",
                    count: OfficialSkillCatalog.maximumSystemImageCharacters + 1
                )
            ),
            definition(sortOrder: -1),
            definition(sortOrder: OfficialSkillCatalog.maximumSortOrder + 1),
            definition(
                englishName: String(
                    repeating: "n",
                    count: OfficialSkillCatalog.maximumNameCharacters + 1
                )
            ),
            definition(
                englishSummary: String(
                    repeating: "s",
                    count: OfficialSkillCatalog.maximumSummaryCharacters + 1
                )
            ),
            definition(
                englishPrompt: String(
                    repeating: "p",
                    count: OfficialSkillCatalog.maximumPromptCharacters + 1
                )
            )
        ]

        for definition in invalidDefinitions {
            XCTAssertThrowsError(
                try OfficialSkillCatalog(revision: 1, skills: [definition]).validated()
            )
        }
    }

    func testInvalidWritePreservesLastKnownGoodSnapshot() throws {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        var good = OfficialSkillCatalog(revision: 4, skills: [definition()])
        good.refreshedAt = Date(timeIntervalSince1970: 100)
        good.etag = "\"rev-4\""
        try store.setOfficialSkillCatalog(good)

        let invalid = OfficialSkillCatalog(
            revision: 5,
            skills: [definition(englishPrompt: "")]
        )
        XCTAssertThrowsError(try store.setOfficialSkillCatalog(invalid))
        XCTAssertEqual(store.officialSkillCatalog.revision, 4)
        XCTAssertEqual(store.officialSkillCatalog.etag, "\"rev-4\"")
    }

    func testMergeOrderAndPrecedenceAreBuiltInOfficialUser() throws {
        let official = OfficialSkillCatalog(
            revision: 1,
            skills: [
                definition(id: AIClipboardSkillCatalog.replyID, sortOrder: 0),
                definition(id: "official.rewrite", sortOrder: 1)
            ]
        )
        var users = AIUserSkillCatalog()
        try users.upsert(AIUserSkill(id: "user.local", name: "Local", prompt: "Local prompt"))

        let merged = AIClipboardSkillCatalog.all(
            officialCatalog: official,
            userCatalog: users,
            uiLanguage: .english
        )

        XCTAssertEqual(merged.filter { $0.id == AIClipboardSkillCatalog.replyID }.count, 1)
        XCTAssertNil(merged.first { $0.id == AIClipboardSkillCatalog.replyID }?.customPrompt)
        XCTAssertEqual(
            Array(merged.suffix(2).map(\.id)),
            ["official.rewrite", "user.local"]
        )
    }

    func testReloadPublishesChangedOfficialCopyWithStableEnabledIDs() throws {
        let defaults = makeDefaults()
        let appGroup = AppGroupStore(defaults: defaults)
        appGroup.setUILanguage(.english)
        var first = OfficialSkillCatalog(
            revision: 1,
            skills: [definition(englishPrompt: "First prompt")]
        )
        first.refreshedAt = Date()
        try appGroup.setOfficialSkillCatalog(first)
        appGroup.setAgentSkillLayout(
            AIAgentSkillLayout(
                enabledIDs: ["official.rewrite"],
                confirmedShortcutIDs: []
            )
        )
        let store = AIAgentSkillLayoutStore(defaults: defaults)
        XCTAssertEqual(store.enabledSkills.first?.customPrompt, "First prompt")

        var second = OfficialSkillCatalog(
            revision: 2,
            skills: [definition(englishPrompt: "Second prompt")]
        )
        second.refreshedAt = Date()
        try appGroup.setOfficialSkillCatalog(second)
        store.reload()

        XCTAssertEqual(store.layout.enabledIDs, ["official.rewrite"])
        XCTAssertEqual(store.enabledSkills.first?.customPrompt, "Second prompt")
    }
}
