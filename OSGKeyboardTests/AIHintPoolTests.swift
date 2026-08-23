// AIHintPoolTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardShared
import XCTest

final class AIHintPoolTests: XCTestCase {
    func testLocaleResolverOnlyZhHansUsesChinesePack() {
        XCTAssertEqual(AIHintLocaleResolver.packLocale(preferredLanguages: ["zh-Hans"]), "zh")
        XCTAssertEqual(AIHintLocaleResolver.packLocale(preferredLanguages: ["zh-Hans-CN"]), "zh")
        XCTAssertEqual(AIHintLocaleResolver.packLocale(preferredLanguages: ["zh-Hant"]), "en")
        XCTAssertEqual(AIHintLocaleResolver.packLocale(preferredLanguages: ["en-US"]), "en")
    }

    func testClipboardWindowNeverPutsClipboardCardsInCarousel() {
        let clipboardCard = AIHintCard(
            id: "remote-clipboard-reply",
            displayText: "回复剪贴板",
            prompt: "请回复剪贴板内容",
            category: "clipboard",
            source: "remote",
            locale: "zh",
            conditions: ["clipboard_30s"]
        )
        let pack = AIHintPack(
            locale: "zh",
            cards: AIHintLocalCatalog.cards(locale: "zh") + [clipboardCard]
        )
        let recent = ClipboardHistoryEntry(text: "hello", createdAt: Date())
        XCTAssertTrue(
            AIHintPool.isClipboardSkillWindowActive(
                clipboardHistoryEnabled: true,
                newestClipboard: recent
            )
        )
        let cards = AIHintPool.activeCards(pack: pack)
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.allSatisfy { !$0.requiresClipboard30s })
    }

    func testLocalCatalogDoesNotDuplicateClipboardSkills() {
        for locale in ["zh", "en"] {
            let cards = AIHintLocalCatalog.cards(locale: locale)
            XCTAssertEqual(cards.count, 4)
            XCTAssertTrue(cards.allSatisfy { !$0.requiresClipboard30s })
            XCTAssertFalse(cards.contains { $0.category == "capability" })
        }
    }

    func testRetiredHintsDoNotResurfaceFromAnOlderReadyPack() {
        let retired = AIHintCard(
            id: "local-zh-quote",
            displayText: "今日金句",
            prompt: "旧版本缓存",
            category: "capability",
            source: "local",
            locale: "zh"
        )
        let retiredRemoteQuote = AIHintCard(
            id: "tophub-daily-soul-old",
            displayText: "今日一句",
            prompt: "旧版本云端缓存",
            category: "daily",
            source: "tophub-daily",
            locale: "zh",
            metadata: AIHintMetadata(soul: "旧金句")
        )
        let cards = AIHintPool.activeCards(
            pack: AIHintPack(locale: "zh", cards: [retired, retiredRemoteQuote])
        )

        XCTAssertFalse(cards.contains { $0.id == retired.id })
        XCTAssertFalse(cards.contains { $0.id == retiredRemoteQuote.id })
        XCTAssertEqual(Set(cards.map(\.id)), Set(AIHintLocalCatalog.cards(locale: "zh").map(\.id)))
    }

    func testResolvePromptEmbedsClipboardMaterialAsData() throws {
        let card = AIHintCard(
            id: "remote-clipboard-reply",
            displayText: "回复剪贴板",
            prompt: "请回复剪贴板内容",
            category: "clipboard",
            source: "remote",
            locale: "zh",
            conditions: ["clipboard_30s"]
        )
        guard case .ready(let prompt) = AIHintPool.resolvePrompt(
            for: card,
            clipboardText: "你好"
        ) else {
            return XCTFail("expected a ready prompt")
        }
        XCTAssertTrue(prompt.contains("<clipboard_text>"))
        XCTAssertTrue(prompt.contains("你好"))
        XCTAssertFalse(prompt.contains(AIClipboardPrompt.materialPlaceholder))
    }

    func testExpiredReadyPackFallsBackToLocalCatalog() {
        let suiteName = "AIHintPoolTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let remoteCard = AIHintCard(
            id: "remote-hot",
            displayText: "聊聊热点",
            prompt: "请概括今日热点",
            category: "society",
            source: "tophub"
        )
        AIHintStore.saveReadyPack(
            AIHintPack(
                locale: "zh",
                expiresAt: "2026-01-01T00:00:00Z",
                cards: [remoteCard]
            ),
            defaults: suite
        )

        let resolved = AIHintStore.resolvedPack(
            locale: "zh",
            now: Date(timeIntervalSince1970: 1_800_000_000),
            defaults: suite
        )

        XCTAssertFalse(resolved.cards.contains { $0.id == remoteCard.id })
        XCTAssertEqual(resolved.cards, AIHintLocalCatalog.cards(locale: "zh"))
    }

    func testFreshReadyPackIsServedAndTrackedPerLocale() {
        let suiteName = "AIHintPoolTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let card = AIHintCard(
            id: "remote-fresh",
            displayText: "看今日早报",
            prompt: "请概括今日要点",
            category: "daily"
        )
        AIHintStore.saveReadyPack(
            AIHintPack(locale: "zh", cards: [card]),
            defaults: suite
        )

        XCTAssertEqual(
            AIHintStore.resolvedPack(locale: "zh", defaults: suite).cards,
            [card]
        )
        XCTAssertFalse(AIHintStore.shouldRefresh(locale: "zh", defaults: suite))
        // en never succeeded, so the pass must still run.
        XCTAssertTrue(AIHintStore.shouldRefresh(locale: "en", defaults: suite))
        XCTAssertTrue(AIHintStore.shouldRefresh(defaults: suite))
    }

    func testKeywordCompressorParseDisplayMap() {
        let raw = #"[{"id":"a","displayText":"聊聊热点"},{"id":"b","displayText":"上海天气怎么样"}]"#
        let map = AIHintKeywordCompressor.parseDisplayMap(from: raw)
        XCTAssertEqual(map["a"], "聊聊热点")
        XCTAssertEqual(map["b"], "上海天气怎么样")
    }

    func testRemotePackDecodesTextAsDisplayText() throws {
        let json = """
        {"locale":"zh","generatedAt":"2026-01-01T00:00:00Z","expiresAt":"2026-01-01T12:00:00Z","version":1,"cards":[{"id":"x","text":"全网热点：很长","prompt":"请概括","category":"society","priority":70,"source":"tophub","locale":"zh","conditions":[]}]}
        """
        let pack = try JSONDecoder().decode(AIHintPack.self, from: Data(json.utf8))
        XCTAssertEqual(pack.cards.first?.displayText, "全网热点：很长")
        XCTAssertEqual(pack.cards.first?.taskKind, .aiQuestion)
    }

    func testCurrentInformationHintDecodesExplicitSearchIntent() throws {
        let json = """
        {"id":"hot","text":"今日热点","prompt":"请概括今日热点","category":"society","locale":"zh","taskKind":"current_information_question"}
        """

        let card = try JSONDecoder().decode(AIHintCard.self, from: Data(json.utf8))

        XCTAssertEqual(card.taskKind, .currentInformationQuestion)
    }

    func testLocalTimeSensitiveHintsRequireCurrentInformation() {
        let cards = AIHintLocalCatalog.cards(locale: "zh")
        XCTAssertEqual(
            cards.map(\.id),
            [
                "local-zh-daily-brief",
                "local-zh-stocks-cn",
                "local-zh-stocks-hk",
                "local-zh-stocks-us"
            ]
        )
        XCTAssertTrue(cards.allSatisfy { $0.taskKind == .currentInformationQuestion })
    }
}
