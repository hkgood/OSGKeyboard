// OfficialSkillCatalogRefreshService.swift
// OSGKeyboard · Main App
//
// Cache-first anonymous refresh for the official Skill Catalog. Invalid
// responses never replace the App Group last-known-good snapshot.

import Foundation
import OSGKeyboardShared

enum OfficialSkillCatalogRefreshOutcome: Equatable, Sendable {
    case skippedFresh
    case updated(revision: Int64)
    case notModified(revision: Int64)
    case failed

    var didUpdateCache: Bool {
        switch self {
        case .updated, .notModified:
            return true
        case .skippedFresh, .failed:
            return false
        }
    }
}

actor OfficialSkillCatalogRefreshService {
    static let shared = OfficialSkillCatalogRefreshService()

    /// App-wide foreground checks stay inexpensive while limiting stale
    /// catalog copy to a short window. The Skills manager forces ETag validation.
    static let refreshInterval: TimeInterval = 15 * 60
    static let endpoint = URL(string: "https://account.osglab.com/v1/content/skills")!

    private let store: AppGroupStore
    private let transport: any PublicContentHTTPTransport
    private let endpointURL: URL
    private let freshnessInterval: TimeInterval
    private var inFlight: Task<OfficialSkillCatalogRefreshOutcome, Never>?

    init(
        store: AppGroupStore = AppGroupStore(),
        transport: any PublicContentHTTPTransport = URLSessionPublicContentHTTPTransport(),
        endpointURL: URL = OfficialSkillCatalogRefreshService.endpoint,
        freshnessInterval: TimeInterval = OfficialSkillCatalogRefreshService.refreshInterval
    ) {
        self.store = store
        self.transport = transport
        self.endpointURL = endpointURL
        self.freshnessInterval = freshnessInterval
    }

    func refreshIfNeeded(
        reason: String,
        now: Date = Date(),
        force: Bool = false
    ) async -> OfficialSkillCatalogRefreshOutcome {
        let cached = store.officialSkillCatalog
        if !force,
           let refreshedAt = cached.refreshedAt,
           now.timeIntervalSince(refreshedAt) < freshnessInterval {
            OSGDiag.log(
                "OfficialSkillCatalog skip fresh reason=\(reason) revision=\(cached.revision)",
                category: "skills"
            )
            return .skippedFresh
        }
        if let inFlight {
            return await inFlight.value
        }

        let task = Task { [store, transport, endpointURL] in
            do {
                return try await Self.performRefresh(
                    store: store,
                    transport: transport,
                    endpointURL: endpointURL,
                    cached: cached,
                    now: now
                )
            } catch {
                OSGDiag.log(
                    "OfficialSkillCatalog failed reason=\(reason) "
                        + "error=\(error.localizedDescription)",
                    category: "skills"
                )
                return .failed
            }
        }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }

    private static func performRefresh(
        store: AppGroupStore,
        transport: any PublicContentHTTPTransport,
        endpointURL: URL,
        cached: OfficialSkillCatalog,
        now: Date
    ) async throws -> OfficialSkillCatalogRefreshOutcome {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = cached.etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await transport.data(for: request)
        switch response.statusCode {
        case 304:
            guard cached.refreshedAt != nil || !cached.skills.isEmpty else {
                throw PublicContentHTTPError.notModifiedWithoutCache
            }
            var refreshed = cached
            refreshed.refreshedAt = now
            refreshed.etag = response.value(forHTTPHeaderField: "ETag") ?? cached.etag
            try store.setOfficialSkillCatalog(refreshed)
            return .notModified(revision: refreshed.revision)
        case 200:
            var received = try JSONDecoder().decode(OfficialSkillCatalog.self, from: data)
            received.refreshedAt = now
            received.etag = response.value(forHTTPHeaderField: "ETag")
            received = try received.validated()
            if cached.refreshedAt != nil, received.revision < cached.revision {
                throw PublicContentHTTPError.staleRevision(
                    current: cached.revision,
                    received: received.revision
                )
            }
            try store.setOfficialSkillCatalog(received)
            return .updated(revision: received.revision)
        default:
            throw PublicContentHTTPError.unexpectedStatus(response.statusCode)
        }
    }
}
