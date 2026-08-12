// AIHintRefreshService.swift
// OSGKeyboard · Main App
//
// Silent 12h refresh: fetch remote packs, compress titles with polish LLM,
// merge local evergreen cards, write App Group ready packs for the keyboard.

import Foundation
import OSGKeyboardShared

@MainActor
enum AIHintRefreshService {
    private static var inFlight: Task<Void, Never>?

    static func refreshIfNeeded(reason: String) {
        guard AIHintStore.shouldRefresh() else {
            OSGDiag.log("AIHintRefresh skip (fresh) reason=\(reason)", category: "hints")
            return
        }
        guard inFlight == nil else {
            OSGDiag.log("AIHintRefresh skip (inFlight) reason=\(reason)", category: "hints")
            return
        }
        inFlight = Task {
            defer { inFlight = nil }
            await runRefresh(reason: reason)
        }
    }

    private static func runRefresh(reason: String) async {
        AIHintStore.markAttempt()
        OSGDiag.log("AIHintRefresh start reason=\(reason)", category: "hints")

        // The manifest only supplies fallback dates, so a manifest failure must
        // not stop the packs, and one locale's failure must not stop the other.
        let manifest = try? await fetchManifest()
        for locale in AIHintFeedEndpoints.supportedLocales {
            if Task.isCancelled { return }
            guard AIHintStore.shouldRefresh(locale: locale) else { continue }
            do {
                let pack = try await readyPack(locale: locale, manifest: manifest)
                AIHintStore.saveReadyPack(pack)
                OSGDiag.log(
                    "AIHintRefresh wrote locale=\(locale) cards=\(pack.cards.count)",
                    category: "hints"
                )
            } catch {
                // Strategy B: keep this locale's previous successful ready pack.
                OSGDiag.log(
                    "AIHintRefresh failed locale=\(locale) reason=\(reason) "
                        + "error=\(error.localizedDescription)",
                    category: "hints"
                )
            }
        }
    }

    private static func readyPack(
        locale: String,
        manifest: AIHintManifest?
    ) async throws -> AIHintPack {
        let remote = try await fetchPack(locale: locale)
        let filtered = remote.cards.filter { card in
            let hay = card.displayText + card.prompt
            return !hay.contains("历史上的今天")
                && !hay.localizedCaseInsensitiveContains("on this day")
        }
        // Prefer remote clipboard cards when present; always keep local evergreen.
        let merged = merge(remote: filtered, locale: locale)
        let compressed = await AIHintKeywordCompressor().compress(
            cards: merged,
            locale: locale
        )
        return AIHintPack(
            locale: locale,
            generatedAt: remote.generatedAt ?? manifest?.generatedAt,
            expiresAt: remote.expiresAt ?? manifest?.expiresAt,
            version: max(remote.version, 1),
            cards: compressed,
            refreshedAt: Date()
        )
    }

    private static func merge(remote: [AIHintCard], locale: String) -> [AIHintCard] {
        var byID: [String: AIHintCard] = [:]
        for card in AIHintLocalCatalog.cards(locale: locale) {
            byID[card.id] = card
        }
        for card in remote {
            // Local clipboard display/prompt stays authoritative when ids collide
            // with baseline remote cards; otherwise remote wins for hot topics.
            if card.requiresClipboard30s, byID[card.id] != nil {
                continue
            }
            if card.source == "local", byID.keys.contains(where: { $0.hasPrefix("local-\(locale)-") }) {
                // Drop remote baseline duplicates when we already have local evergreen.
                if ["clipboard", "capability", "economy"].contains(card.category) {
                    continue
                }
            }
            byID[card.id] = card
        }
        return Array(byID.values).sorted { $0.priority > $1.priority }
    }

    private static func fetchManifest() async throws -> AIHintManifest {
        let (data, response) = try await URLSession.shared.data(from: AIHintFeedEndpoints.manifestURL)
        try validateHTTP(response)
        return try JSONDecoder().decode(AIHintManifest.self, from: data)
    }

    private static func fetchPack(locale: String) async throws -> AIHintPack {
        let url = AIHintFeedEndpoints.packURL(locale: locale)
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTP(response)
        return try JSONDecoder().decode(AIHintPack.self, from: data)
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
