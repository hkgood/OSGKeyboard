// PublicContentRefreshServiceTests.swift
// OSGKeyboardTests

@testable import OSGKeyboard
@testable import OSGKeyboardShared
import XCTest

private struct PublicContentStubResponse: Sendable {
    let statusCode: Int
    let data: Data
    let headers: [String: String]
}

private actor QueuePublicContentTransport: PublicContentHTTPTransport {
    private var responses: [PublicContentStubResponse]
    private var requests: [URLRequest] = []
    private let delay: Duration?

    init(responses: [PublicContentStubResponse], delay: Duration? = nil) {
        self.responses = responses
        self.delay = delay
    }

    func append(_ response: PublicContentStubResponse) {
        responses.append(response)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let delay {
            try await Task.sleep(for: delay)
        }
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let stub = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        return (stub.data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

@MainActor
final class PublicContentRefreshServiceTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "group.com.osgkeyboard.shared.tests.publicContent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private var validCatalogData: Data {
        Data(
            """
            {
              "schemaVersion": 1,
              "revision": 12,
              "generatedAt": "2026-08-21T03:00:00Z",
              "skills": [{
                "id": "official.rewrite",
                "systemImage": "wand.and.stars",
                "sortOrder": 10,
                "kind": "transform",
                "thinkingEnabled": true,
                "localizations": {
                  "zh-Hans": {
                    "name": "改写",
                    "summary": "清晰改写剪贴板内容",
                    "prompt": "请清晰改写剪贴板内容。"
                  },
                  "en": {
                    "name": "Rewrite",
                    "summary": "Rewrite clipboard text clearly",
                    "prompt": "Rewrite the clipboard clearly."
                  }
                }
              }]
            }
            """.utf8
        )
    }

    func testOfficialForcedRefreshBypassesFreshnessAndUsesETag304() async throws {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        let transport = QueuePublicContentTransport(
            responses: [
                PublicContentStubResponse(
                    statusCode: 200,
                    data: validCatalogData,
                    headers: ["ETag": "\"skills-12\""]
                )
            ]
        )
        let service = OfficialSkillCatalogRefreshService(
            store: store,
            transport: transport,
            endpointURL: URL(string: "https://example.test/v1/content/skills")!
        )
        let firstDate = Date(timeIntervalSince1970: 1_000)

        let first = await service.refreshIfNeeded(
            reason: "test",
            now: firstDate,
            force: true
        )
        XCTAssertEqual(first, .updated(revision: 12))
        XCTAssertEqual(store.officialSkillCatalog.etag, "\"skills-12\"")
        XCTAssertEqual(store.officialSkillCatalog.refreshedAt, firstDate)

        await transport.append(
            PublicContentStubResponse(
                statusCode: 304,
                data: Data(),
                headers: ["ETag": "\"skills-12\""]
            )
        )
        // Sixty seconds remains inside ordinary freshness, but the Skills
        // manager's forced check must still revalidate with the cached ETag.
        let secondDate = firstDate.addingTimeInterval(60)
        let second = await service.refreshIfNeeded(
            reason: "test-304",
            now: secondDate,
            force: true
        )

        XCTAssertEqual(second, .notModified(revision: 12))
        XCTAssertEqual(store.officialSkillCatalog.refreshedAt, secondDate)
        XCTAssertEqual(store.officialSkillCatalog.skills.first?.id, "official.rewrite")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.last?.value(forHTTPHeaderField: "If-None-Match"),
            "\"skills-12\""
        )
    }

    func testOfficialRefreshRejectsInvalidResponseAndKeepsCache() async throws {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        var cached = try JSONDecoder().decode(OfficialSkillCatalog.self, from: validCatalogData)
        cached.refreshedAt = Date(timeIntervalSince1970: 100)
        cached.etag = "\"good\""
        try store.setOfficialSkillCatalog(cached)
        let invalid = Data(
            """
            {"schemaVersion":2,"revision":13,"skills":[]}
            """.utf8
        )
        let transport = QueuePublicContentTransport(
            responses: [
                PublicContentStubResponse(statusCode: 200, data: invalid, headers: [:])
            ]
        )
        let service = OfficialSkillCatalogRefreshService(
            store: store,
            transport: transport
        )

        let outcome = await service.refreshIfNeeded(reason: "invalid", force: true)

        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(store.officialSkillCatalog.revision, 12)
        XCTAssertEqual(store.officialSkillCatalog.etag, "\"good\"")
    }

    func testOfficialRefreshUsesFreshCacheWithoutNetwork() async throws {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        let refreshedAt = Date(timeIntervalSince1970: 1_000)
        var cached = try JSONDecoder().decode(OfficialSkillCatalog.self, from: validCatalogData)
        cached.refreshedAt = refreshedAt
        try store.setOfficialSkillCatalog(cached)
        let transport = QueuePublicContentTransport(responses: [])
        let service = OfficialSkillCatalogRefreshService(
            store: store,
            transport: transport
        )

        let outcome = await service.refreshIfNeeded(
            reason: "fresh-cache",
            now: refreshedAt.addingTimeInterval(60)
        )

        XCTAssertEqual(outcome, .skippedFresh)
        XCTAssertEqual(OfficialSkillCatalogRefreshService.refreshInterval, 15 * 60)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testOfficialForcedRefreshDeduplicatesConcurrentFreshCacheRequests() async throws {
        let defaults = makeDefaults()
        let store = AppGroupStore(defaults: defaults)
        var cached = try JSONDecoder().decode(OfficialSkillCatalog.self, from: validCatalogData)
        cached.refreshedAt = Date()
        cached.etag = "\"skills-12\""
        try store.setOfficialSkillCatalog(cached)
        let transport = QueuePublicContentTransport(
            responses: [
                PublicContentStubResponse(
                    statusCode: 304,
                    data: Data(),
                    headers: [:]
                )
            ],
            delay: .milliseconds(50)
        )
        let service = OfficialSkillCatalogRefreshService(
            store: store,
            transport: transport
        )

        async let first = service.refreshIfNeeded(reason: "first", force: true)
        async let second = service.refreshIfNeeded(reason: "second", force: true)
        let outcomes = await (first, second)

        XCTAssertEqual(outcomes.0, .notModified(revision: 12))
        XCTAssertEqual(outcomes.1, .notModified(revision: 12))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testHintRefreshUsesAccountPathsAndPreservesPacksOn304() async {
        let defaults = makeDefaults()
        let oldDate = Date(timeIntervalSince1970: 100)
        for locale in AIHintFeedEndpoints.supportedLocales {
            AIHintStore.saveReadyPack(
                AIHintPack(
                    locale: locale,
                    cards: [
                        AIHintCard(
                            id: "cached-\(locale)",
                            displayText: "Cached",
                            prompt: "Keep me",
                            category: "general",
                            locale: locale
                        )
                    ],
                    refreshedAt: oldDate
                ),
                defaults: defaults
            )
            AIHintStore.setPackETag(
                "\"\(locale)-etag\"",
                locale: locale,
                defaults: defaults
            )
        }
        AIHintStore.setManifestETag("\"manifest-etag\"", defaults: defaults)
        let notModified = PublicContentStubResponse(
            statusCode: 304,
            data: Data(),
            headers: [:]
        )
        let transport = QueuePublicContentTransport(
            responses: [notModified, notModified, notModified]
        )
        let baseURL = URL(string: "https://account.osglab.com/v1/content/hints")!
        let service = AIHintRefreshService(
            transport: transport,
            defaults: defaults,
            baseURL: baseURL
        )
        let now = Date(timeIntervalSince1970: 5_000)

        let outcome = await service.refreshNowIfNeeded(
            reason: "test-304",
            now: now,
            force: true
        )

        XCTAssertEqual(outcome, .completed(updatedLocales: ["zh", "en"]))
        XCTAssertEqual(
            AIHintStore.loadReadyPack(locale: "zh", defaults: defaults)?.cards.first?.prompt,
            "Keep me"
        )
        XCTAssertEqual(
            AIHintStore.loadReadyPack(locale: "zh", defaults: defaults)?.refreshedAt,
            now
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.map { $0.url?.path }, [
            "/v1/content/hints/manifest",
            "/v1/content/hints/zh",
            "/v1/content/hints/en"
        ])
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "If-None-Match"),
            "\"zh-etag\""
        )
    }

    func testPublishedHintEndpointsUseAnonymousAccountContentRoutes() {
        XCTAssertEqual(
            AIHintFeedEndpoints.manifestURL.absoluteString,
            "https://account.osglab.com/v1/content/hints/manifest"
        )
        XCTAssertEqual(
            AIHintFeedEndpoints.packURL(locale: "zh").absoluteString,
            "https://account.osglab.com/v1/content/hints/zh"
        )
    }
}
