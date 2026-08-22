// AIHintRefreshService.swift
// OSGKeyboard · Main App
//
        // Silent 12h refresh: fetch remote packs, extract keywords (LLM only
        // for leftovers), merge local evergreen cards, write App Group ready
        // packs for the keyboard.

import Foundation
import OSGKeyboardShared

enum AIHintRefreshOutcome: Equatable {
    case skippedFresh
    case completed(updatedLocales: [String])
}

@MainActor
final class AIHintRefreshService {
    static let shared = AIHintRefreshService()

    private let transport: any PublicContentHTTPTransport
    private let defaults: UserDefaults?
    private let baseURL: URL
    private var inFlight: Task<AIHintRefreshOutcome, Never>?

    init(
        transport: any PublicContentHTTPTransport = URLSessionPublicContentHTTPTransport(),
        defaults: UserDefaults? = AppGroup.defaultsIfAvailable,
        baseURL: URL = AIHintFeedEndpoints.baseURL
    ) {
        self.transport = transport
        self.defaults = defaults
        self.baseURL = baseURL
    }

    static func refreshIfNeeded(reason: String) {
        shared.scheduleRefreshIfNeeded(reason: reason)
    }

    func scheduleRefreshIfNeeded(reason: String) {
        guard inFlight == nil else {
            OSGDiag.log("AIHintRefresh skip (inFlight) reason=\(reason)", category: "hints")
            return
        }
        inFlight = Task {
            defer { inFlight = nil }
            return await refreshNowIfNeeded(reason: reason)
        }
    }

    func refreshNowIfNeeded(
        reason: String,
        now: Date = Date(),
        force: Bool = false
    ) async -> AIHintRefreshOutcome {
        if !force, !AIHintStore.shouldRefresh(now: now, defaults: defaults) {
            OSGDiag.log("AIHintRefresh skip (fresh) reason=\(reason)", category: "hints")
            return .skippedFresh
        }

        AIHintStore.markAttempt(defaults: defaults)
        OSGDiag.log("AIHintRefresh start reason=\(reason)", category: "hints")

        // The manifest only supplies fallback dates, so a manifest failure must
        // not stop the packs, and one locale's failure must not stop the other.
        let manifest = (try? await fetchManifest()) ?? AIHintStore.loadManifest(defaults: defaults)
        var updatedLocales: [String] = []
        for locale in AIHintFeedEndpoints.supportedLocales {
            if Task.isCancelled { break }
            if !force,
               !AIHintStore.shouldRefresh(locale: locale, now: now, defaults: defaults) {
                continue
            }
            do {
                try await refreshPack(locale: locale, manifest: manifest, now: now)
                updatedLocales.append(locale)
            } catch {
                // Strategy B: keep this locale's previous successful ready pack.
                OSGDiag.log(
                    "AIHintRefresh failed locale=\(locale) reason=\(reason) "
                        + "error=\(error.localizedDescription)",
                    category: "hints"
                )
            }
        }
        return .completed(updatedLocales: updatedLocales)
    }

    private func refreshPack(
        locale: String,
        manifest: AIHintManifest?,
        now: Date
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(locale))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = AIHintStore.packETag(locale: locale, defaults: defaults) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await transport.data(for: request)

        if response.statusCode == 304 {
            guard var existing = AIHintStore.loadReadyPack(locale: locale, defaults: defaults) else {
                throw PublicContentHTTPError.notModifiedWithoutCache
            }
            existing.refreshedAt = now
            AIHintStore.saveReadyPack(existing, defaults: defaults)
            if let etag = response.value(forHTTPHeaderField: "ETag") {
                AIHintStore.setPackETag(etag, locale: locale, defaults: defaults)
            }
            OSGDiag.log("AIHintRefresh kept locale=\(locale) (304)", category: "hints")
            return
        }
        guard response.statusCode == 200 else {
            throw PublicContentHTTPError.unexpectedStatus(response.statusCode)
        }

        let remote = try JSONDecoder().decode(AIHintPack.self, from: data)
        let filtered = remote.cards.filter { card in
            let hay = card.displayText + card.prompt
            return !hay.contains("历史上的今天")
                && !hay.localizedCaseInsensitiveContains("on this day")
        }
        // Prefer remote clipboard cards when present; always keep local evergreen.
        let merged = Self.merge(remote: filtered, locale: locale)
        let compressed = await AIHintKeywordCompressor().compress(
            cards: merged,
            locale: locale
        )
        let ready = AIHintPack(
            locale: locale,
            generatedAt: remote.generatedAt ?? manifest?.generatedAt,
            expiresAt: remote.expiresAt ?? manifest?.expiresAt,
            version: max(remote.version, 1),
            cards: compressed,
            refreshedAt: now
        )
        AIHintStore.saveReadyPack(ready, defaults: defaults)
        AIHintStore.setPackETag(
            response.value(forHTTPHeaderField: "ETag"),
            locale: locale,
            defaults: defaults
        )
        OSGDiag.log(
            "AIHintRefresh wrote locale=\(locale) cards=\(ready.cards.count)",
            category: "hints"
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

    private func fetchManifest() async throws -> AIHintManifest? {
        var request = URLRequest(url: baseURL.appendingPathComponent("manifest"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = AIHintStore.manifestETag(defaults: defaults) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 304 {
            return AIHintStore.loadManifest(defaults: defaults)
        }
        guard response.statusCode == 200 else {
            throw PublicContentHTTPError.unexpectedStatus(response.statusCode)
        }
        let manifest = try JSONDecoder().decode(AIHintManifest.self, from: data)
        AIHintStore.saveManifest(
            manifest,
            etag: response.value(forHTTPHeaderField: "ETag"),
            defaults: defaults
        )
        return manifest
    }
}
