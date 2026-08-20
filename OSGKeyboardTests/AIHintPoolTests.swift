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
        let pack = AIHintPack(
            locale: "zh",
            cards: AIHintLocalCatalog.cards(locale: "zh")
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

    func testClipboardDisabledDropsClipboardCards() {
        let pack = AIHintPack(
            locale: "zh",
            cards: AIHintLocalCatalog.cards(locale: "zh")
        )
        let cards = AIHintPool.activeCards(pack: pack)
        XCTAssertFalse(cards.isEmpty)
        XCTAssertTrue(cards.allSatisfy { !$0.requiresClipboard30s })
    }

    func testResolvePromptEmbedsClipboardMaterialAsData() throws {
        let card = AIHintLocalCatalog.cards(locale: "zh")
            .first { $0.id == "local-zh-clipboard-reply" }!
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
    }
}
