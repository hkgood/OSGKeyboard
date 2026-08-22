// ManagedGatewayTests.swift
// OSGKeyboard · Extension Tests
//
// Hermetic grant rotation and managed LLM tests using a private URLProtocol stub.

import Foundation
@testable import OSGKeyboardShared
import XCTest

final class ManagedGatewayTests: XCTestCase {
    private let baseURL = URL(string: "https://gateway.test")!

    override func setUp() {
        super.setUp()
        GatewayStub.shared.reset()
    }

    override func tearDown() {
        GatewayStub.shared.reset()
        super.tearDown()
    }

    func testFiveMinuteAccessBoundaryAndScope() {
        let start = Date(timeIntervalSince1970: 1_000)
        let value = credentials(accessExpiresAt: start.addingTimeInterval(3_600), receivedAt: start)
        XCTAssertEqual(value.effectiveAccessExpiresAt, start.addingTimeInterval(300))
        XCTAssertTrue(value.hasUsableAccessToken(for: .polish, at: start.addingTimeInterval(269)))
        XCTAssertFalse(value.hasUsableAccessToken(for: .polish, at: start.addingTimeInterval(270)))
        XCTAssertFalse(value.hasUsableAccessToken(for: .asr, at: start))
    }

    func testScopePolicyExcludesASRForLocalEngineAndIncludesItForCloud() {
        let localScopes = ManagedGatewayScopePolicy.scopes(engineMode: "local")
        XCTAssertEqual(localScopes, [.polish, .assistant, .agent])
        XCTAssertFalse(localScopes.contains(.asr))

        let cloudScopes = ManagedGatewayScopePolicy.scopes(engineMode: "cloud")
        XCTAssertEqual(cloudScopes, [.polish, .assistant, .agent, .asr])
    }

    func testOOBEFeatureConflictIsNotMappedToNetworkFailure() {
        let error = ManagedGatewayHTTP.error(
            data: errorJSON("oobe_feature_already_used"),
            status: 409,
            requestId: "oobe-conflict"
        )

        XCTAssertEqual(error, .oobeFeatureAlreadyUsed)
    }

    func testCreateGrantSendsAccountTokenButStoresOnlyGrant() async throws {
        GatewayStub.shared.enqueue(
            201,
            grantJSON(
                access: "grant-access",
                refresh: "grant-refresh",
                scopes: ["polish", "ai"]
            )
        )
        let store = MemoryGrantStore()
        let coordinator = makeCoordinator(store: store)

        _ = try await coordinator.createGrant(
            accountAccessToken: "account-secret",
            scopes: [.polish, .assistant],
            lifetimeSeconds: 3_600,
            idempotencyKey: "create-idempotency"
        )

        let stored = await store.value()
        XCTAssertEqual(stored?.refreshToken, "grant-refresh")
        let request = try XCTUnwrap(GatewayStub.shared.requests().first)
        XCTAssertEqual(request.url?.path, "/v1/gateway/grants")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer account-secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "create-idempotency")
        let body = try jsonBody(request)
        XCTAssertEqual(Set(body["scopes"] as? [String] ?? []), Set(["polish", "ai"]))
        XCTAssertEqual(body["lifetimeSeconds"] as? Int, 3_600)
        let persisted = try JSONEncoder().encode(stored)
        XCTAssertFalse(
            (String(bytes: persisted, encoding: .utf8) ?? "").contains("account-secret")
        )
    }

    func testCreateGrantRejectsBroaderReturnedScopes() async throws {
        GatewayStub.shared.enqueue(
            201,
            grantJSON(
                access: "grant-access",
                refresh: "grant-refresh",
                scopes: ["polish", "ai", "agent"]
            )
        )
        let store = MemoryGrantStore()
        let coordinator = makeCoordinator(store: store)

        await XCTAssertThrowsManaged(.invalidGrant) {
            _ = try await coordinator.createGrant(
                accountAccessToken: "account-secret",
                scopes: [.polish],
                idempotencyKey: "create-scope-boundary"
            )
        }
        let stored = await store.value()
        XCTAssertNil(stored)
    }

    func testConcurrentRefreshIsMergedAndHashesOldTokenForIdempotency() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let oldRefresh = "old-refresh-token-that-is-at-least-32-characters"
        let store = MemoryGrantStore(
            credentials(
                accessToken: "expired",
                refreshToken: oldRefresh,
                accessExpiresAt: now.addingTimeInterval(-1),
                receivedAt: now.addingTimeInterval(-600)
            )
        )
        GatewayStub.shared.enqueue(
            200,
            grantJSON(access: "new-access", refresh: "new-refresh"),
            delay: 0.05
        )
        let coordinator = makeCoordinator(store: store, now: { now })

        async let first = coordinator.accessToken(for: .assistant)
        async let second = coordinator.accessToken(for: .assistant)
        let values = try await (first, second)

        XCTAssertEqual(values.0, "new-access")
        XCTAssertEqual(values.1, "new-access")
        let requests = GatewayStub.shared.requests()
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(key, GatewayGrantCoordinator.refreshTokenIdempotencyKey(oldRefresh))
        XCTAssertFalse(key.contains(oldRefresh))
        XCTAssertEqual(try jsonBody(request)["refreshToken"] as? String, oldRefresh)
    }

    func testSignedOutPolicyRejectsCachedAccountGrant() async throws {
        let suiteName = "ManagedGatewayTests.signedOut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 3_000)
        let store = MemoryGrantStore(
            credentials(
                accessToken: "cached-account-access",
                accessExpiresAt: now.addingTimeInterval(240),
                refreshExpiresAt: now.addingTimeInterval(3_600),
                receivedAt: now
            )
        )
        let accountState = AppGroupStore(defaults: defaults)
        let coordinator = GatewayGrantCoordinator(
            baseURL: baseURL,
            store: store,
            session: stubSession(),
            now: { now },
            accountAccessPolicy: AppGroupManagedGatewayAccountAccessPolicy(
                defaults: defaults
            )
        )

        await XCTAssertThrowsManaged(.missingGrant) {
            _ = try await coordinator.accessToken(for: .polish)
        }
        XCTAssertTrue(GatewayStub.shared.requests().isEmpty)

        accountState.setManagedGatewayAccountSessionAvailable(true)
        let token = try await coordinator.accessToken(for: .polish)
        XCTAssertEqual(token, "cached-account-access")
    }

    func testManagedClientMapsAllCapabilitiesHeadersBodyAndRequestIds() async throws {
        let now = Date(timeIntervalSince1970: 3_000)
        let store = MemoryGrantStore(credentials(accessToken: "access", receivedAt: now))
        let coordinator = makeCoordinator(store: store, now: { now })
        let ids = LockedValues(["request-0001", "request-0002", "request-0003"])

        let cases: [(ManagedLLMClient.Capability, ManagedGatewayTaskKind)] = [
            (.polish, .dictationPolish),
            (.assistant, .aiQuestion),
            (.agent, .agentPlanning)
        ]
        for (capability, _) in cases {
            GatewayStub.shared.enqueue(200, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
            let client = ManagedLLMClient(
                capability: capability,
                grants: coordinator,
                baseURL: baseURL,
                session: stubSession(),
                requestId: { ids.next() }
            )
            let result = try await client.polish(
                "input",
                systemPrompt: "context",
                timeout: 7,
                options: LLMGenerationOptions(temperature: 0.4, maxTokens: 321)
            )
            XCTAssertEqual(result, "ok")
        }

        let requests = GatewayStub.shared.requests()
        XCTAssertEqual(
            requests.compactMap(\.url?.path),
            [
                "/v1/gateway/llm/polish",
                "/v1/gateway/llm/ai",
                "/v1/gateway/llm/agent"
            ]
        )
        XCTAssertEqual(Set(requests.compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }).count, 3)
        for (request, expectedCase) in zip(requests, cases) {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            let body = try jsonBody(request)
            XCTAssertEqual(body["input"] as? String, "input")
            XCTAssertEqual(body["context"] as? String, "context")
            XCTAssertEqual(body["maxOutputTokens"] as? Int, 321)
            XCTAssertEqual(body["temperature"] as? Double, 0.4)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["taskKind"] as? String, expectedCase.1.rawValue)
            XCTAssertEqual(request.timeoutInterval, 7)
        }
    }

    func testManagedClientSerializesFineGrainedTaskKinds() async throws {
        let now = Date(timeIntervalSince1970: 3_500)
        let store = MemoryGrantStore(credentials(accessToken: "access", receivedAt: now))
        let coordinator = makeCoordinator(store: store, now: { now })
        let cases: [(ManagedLLMClient.Capability, ManagedGatewayTaskKind)] = [
            (.polish, .translation),
            (.polish, .editLastInput),
            (.assistant, .currentInformationQuestion),
            (.assistant, .clipboardTransform),
            (.assistant, .customSkill)
        ]

        for (capability, taskKind) in cases {
            GatewayStub.shared.enqueue(200, Data(#"{"output_text":"ok"}"#.utf8))
            let client = ManagedLLMClient(
                capability: capability,
                taskKind: taskKind,
                grants: coordinator,
                baseURL: baseURL,
                session: stubSession()
            )
            _ = try await client.polish("input", systemPrompt: "context")
        }

        let taskKinds = try GatewayStub.shared.requests().map {
            try XCTUnwrap(jsonBody($0)["taskKind"] as? String)
        }
        XCTAssertEqual(taskKinds, cases.map { $0.1.rawValue })
    }

    func testManagedClientSerializesOOBERequestPurpose() async throws {
        let now = Date(timeIntervalSince1970: 3_750)
        let store = MemoryGrantStore(credentials(accessToken: "account-access", receivedAt: now))
        let oobeStore = MemoryGrantStore(
            credentials(
                accessToken: "oobe-access",
                receivedAt: now,
                scopes: [.polish, .assistant]
            )
        )
        let suite = "managed.oobe.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let practice = try XCTUnwrap(
            KeyboardSetupBridge.beginOOBEPracticeSession(
                expectedFeature: .voiceInput,
                defaults: defaults,
                now: now
            )
        )
        XCTAssertEqual(practice.expectedFeature, .voiceInput)
        GatewayStub.shared.enqueue(200, Data(#"{"output_text":"ok"}"#.utf8))
        let client = ManagedLLMClient(
            capability: .polish,
            taskKind: .dictationPolish,
            requestPurpose: .oobe,
            oobeFeature: .voiceInput,
            grants: makeCoordinator(store: store, now: { now }),
            oobeGrants: OOBEGatewayGrantCoordinator(
                baseURL: baseURL,
                store: oobeStore,
                session: stubSession(),
                now: { now },
                practiceSession: { practice }
            ),
            baseURL: baseURL,
            session: stubSession()
        )

        _ = try await client.polish("input", systemPrompt: "context")

        let request = try XCTUnwrap(GatewayStub.shared.requests().last)
        let body = try jsonBody(request)
        XCTAssertEqual(body["taskKind"] as? String, "dictation_polish")
        XCTAssertEqual(body["requestPurpose"] as? String, "oobe")
        XCTAssertEqual(body["oobeFeature"] as? String, "voice_input")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer oobe-access")
        let accountCredentials = await store.value()
        XCTAssertEqual(accountCredentials?.accessToken, "account-access")
    }

    func testOOBEGrantRejectsAgentOrASRScopes() async {
        let now = Date(timeIntervalSince1970: 3_775)
        let coordinator = OOBEGatewayGrantCoordinator(
            baseURL: baseURL,
            store: MemoryGrantStore(),
            session: stubSession(),
            now: { now }
        )

        await XCTAssertThrowsManaged(.invalidGrant) {
            try await coordinator.install(
                self.credentials(
                    receivedAt: now,
                    scopes: [.polish, .assistant, .agent]
                )
            )
        }
        await XCTAssertThrowsManaged(.invalidGrant) {
            try await coordinator.install(
                self.credentials(
                    receivedAt: now,
                    scopes: [.polish, .assistant, .asr]
                )
            )
        }
    }

    func testOOBERefreshUsesDedicatedEndpoint() async throws {
        let now = Date(timeIntervalSince1970: 3_790)
        let practice = OOBEPracticeSession(
            sessionID: UUID(),
            expectedFeature: .voiceInput,
            startedAt: now.addingTimeInterval(-10),
            expiresAt: now.addingTimeInterval(300)
        )
        let store = MemoryGrantStore(
            credentials(
                accessToken: "expired",
                accessExpiresAt: now.addingTimeInterval(-1),
                receivedAt: now.addingTimeInterval(-600),
                scopes: [.polish, .assistant]
            )
        )
        GatewayStub.shared.enqueue(
            200,
            grantJSON(
                access: "refreshed",
                refresh: "rotated",
                scopes: ["polish", "ai"]
            )
        )
        let coordinator = OOBEGatewayGrantCoordinator(
            baseURL: baseURL,
            store: store,
            session: stubSession(),
            now: { now },
            practiceSession: { practice }
        )

        let token = try await coordinator.accessToken(
            for: .polish,
            feature: .voiceInput
        )

        XCTAssertEqual(token, "refreshed")
        XCTAssertEqual(
            GatewayStub.shared.requests().first?.url?.path,
            "/v1/oobe/grants/refresh"
        )
    }

    func testOOBEClientRejectsMissingFeatureWithoutUsingAccountGrant() async {
        let now = Date(timeIntervalSince1970: 3_800)
        let store = MemoryGrantStore(credentials(accessToken: "account-access", receivedAt: now))
        let client = ManagedLLMClient(
            capability: .polish,
            requestPurpose: .oobe,
            grants: makeCoordinator(store: store, now: { now }),
            baseURL: baseURL,
            session: stubSession()
        )

        await XCTAssertThrowsManaged(
            .server(code: "missing_oobe_feature", status: 400, requestId: "fixed")
        ) {
            _ = try await ManagedLLMClient(
                capability: client.capability,
                requestPurpose: client.requestPurpose,
                grants: makeCoordinator(store: store, now: { now }),
                baseURL: self.baseURL,
                session: self.stubSession(),
                requestId: { "fixed" }
            ).polish("input", systemPrompt: "context")
        }
        XCTAssertTrue(GatewayStub.shared.requests().isEmpty)
    }

    func testManagedTaskKindWireValuesMatchServerContract() {
        XCTAssertEqual(
            ManagedGatewayTaskKind.allCases.map(\.rawValue),
            [
                "dictation_polish",
                "translation",
                "edit_last_input",
                "ai_question",
                "current_information_question",
                "clipboard_transform",
                "custom_skill",
                "agent_planning"
            ]
        )
    }

    func testConversationMappingAndRawTextFallback() async throws {
        let now = Date(timeIntervalSince1970: 4_000)
        let store = MemoryGrantStore(credentials(accessToken: "access", receivedAt: now))
        GatewayStub.shared.enqueue(200, Data("raw answer".utf8), contentType: "text/plain")
        let client = ManagedLLMClient(
            capability: .assistant,
            grants: makeCoordinator(store: store, now: { now }),
            baseURL: baseURL,
            session: stubSession()
        )

        let answer = try await client.complete(
            messages: [.system("system"), .user("old"), .assistant("reply"), .user("latest")],
            timeout: nil,
            options: .polishDefault
        )

        XCTAssertEqual(answer, "raw answer")
        let request = try XCTUnwrap(GatewayStub.shared.requests().first)
        let body = try jsonBody(request)
        XCTAssertEqual(body["input"] as? String, "latest")
        XCTAssertEqual(body["context"] as? String, "system:\nsystem\n\nuser:\nold\n\nassistant:\nreply")
    }

    func testUnauthorizedRequestRefreshesOnceWithSameRequestId() async throws {
        let now = Date(timeIntervalSince1970: 5_000)
        let oldRefresh = "old-refresh-value-123456789012345678901"
        let store = MemoryGrantStore(
            credentials(accessToken: "old-access", refreshToken: oldRefresh, receivedAt: now)
        )
        GatewayStub.shared.enqueue(401, errorJSON("unauthorized"))
        GatewayStub.shared.enqueue(200, grantJSON(access: "new-access", refresh: "new-refresh"))
        GatewayStub.shared.enqueue(200, Data(#"{"output_text":"done"}"#.utf8))
        let client = ManagedLLMClient(
            capability: .polish,
            grants: makeCoordinator(store: store, now: { now }),
            baseURL: baseURL,
            session: stubSession(),
            requestId: { "logical-request" }
        )

        let result = try await client.polish("input", systemPrompt: "prompt")
        XCTAssertEqual(result, "done")
        let requests = GatewayStub.shared.requests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer old-access")
        XCTAssertEqual(requests[1].url?.path, "/v1/gateway/grants/refresh")
        XCTAssertEqual(requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "X-Request-ID"),
            requests[2].value(forHTTPHeaderField: "X-Request-ID")
        )
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Idempotency-Key"),
            GatewayGrantCoordinator.refreshTokenIdempotencyKey(oldRefresh)
        )
    }

    func testCreditAndInvalidRefreshErrorsAreMapped() async throws {
        let now = Date(timeIntervalSince1970: 6_000)
        let creditStore = MemoryGrantStore(credentials(accessToken: "access", receivedAt: now))
        GatewayStub.shared.enqueue(402, errorJSON("insufficient_credits"))
        let creditClient = ManagedLLMClient(
            capability: .assistant,
            grants: makeCoordinator(store: creditStore, now: { now }),
            baseURL: baseURL,
            session: stubSession()
        )
        await XCTAssertThrowsManaged(.insufficientCredits) {
            _ = try await creditClient.complete(
                messages: [.user("question")],
                timeout: nil,
                options: .polishDefault
            )
        }

        let expiredStore = MemoryGrantStore(
            credentials(
                accessToken: "expired",
                accessExpiresAt: now.addingTimeInterval(-1),
                receivedAt: now.addingTimeInterval(-600)
            )
        )
        GatewayStub.shared.enqueue(401, errorJSON("invalid_gateway_refresh"))
        let coordinator = makeCoordinator(store: expiredStore, now: { now })
        await XCTAssertThrowsManaged(.invalidGrant) {
            _ = try await coordinator.accessToken(for: .assistant)
        }
        let remaining = await expiredStore.value()
        XCTAssertNil(remaining)
    }

    func testTransportTimeoutMapsToManagedTimeout() async {
        let now = Date(timeIntervalSince1970: 6_500)
        let store = MemoryGrantStore(credentials(accessToken: "access", receivedAt: now))
        GatewayStub.shared.enqueue(
            0,
            Data(),
            transportError: .timedOut
        )
        let client = ManagedLLMClient(
            capability: .polish,
            grants: makeCoordinator(store: store, now: { now }),
            baseURL: baseURL,
            session: stubSession()
        )

        await XCTAssertThrowsManaged(.timeout) {
            _ = try await client.polish("input", systemPrompt: "prompt", timeout: 0.1)
        }
    }

    func testCancellationAndStreaming() async throws {
        let now = Date(timeIntervalSince1970: 7_000)
        let store = MemoryGrantStore(credentials(accessToken: "access", receivedAt: now))
        let coordinator = makeCoordinator(store: store, now: { now })
        GatewayStub.shared.enqueue(200, Data(#"{"output_text":"late"}"#.utf8), delay: 5)
        let cancelledClient = ManagedLLMClient(
            capability: .polish,
            grants: coordinator,
            baseURL: baseURL,
            session: stubSession()
        )
        let task = Task { try await cancelledClient.polish("input", systemPrompt: "prompt") }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch let error as LLMError {
            XCTAssertEqual(error, .cancelled)
        } catch is CancellationError {
            // Foundation may surface native cancellation before client mapping.
        }

        let sse = """
        data: {"choices":[{"delta":{"reasoning_content":"hidden","content":"Hello"}}]}

        data: {"type":"response.output_text.delta","delta":" world"}

        data: [DONE]

        """
        GatewayStub.shared.enqueue(200, Data(sse.utf8), contentType: "text/event-stream")
        let streamClient = ManagedLLMClient(
            capability: .assistant,
            grants: coordinator,
            baseURL: baseURL,
            session: stubSession()
        )
        var answer = ""
        for try await event in streamClient.completeStreaming(
            messages: [.user("question")],
            timeout: 2,
            options: .polishDefault
        ) {
            if case .delta(let value) = event { answer += value }
        }
        XCTAssertEqual(answer, "Hello world")
        let streamRequest = try XCTUnwrap(GatewayStub.shared.requests().last)
        XCTAssertEqual(try jsonBody(streamRequest)["stream"] as? Bool, true)
    }

    private func makeCoordinator(
        store: MemoryGrantStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> GatewayGrantCoordinator {
        GatewayGrantCoordinator(
            baseURL: baseURL,
            store: store,
            session: stubSession(),
            now: now,
            accountAccessPolicy: UnrestrictedManagedGatewayAccountAccessPolicy()
        )
    }

    private func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GatewayURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func credentials(
        accessToken: String = "access-token",
        refreshToken: String = "refresh-token-value-12345678901234567890",
        accessExpiresAt: Date = Date(timeIntervalSince1970: 20_000),
        refreshExpiresAt: Date = Date(timeIntervalSince1970: 40_000),
        receivedAt: Date = Date(timeIntervalSince1970: 10_000),
        scopes: Set<ManagedGatewayCapability> = [.polish, .assistant, .agent]
    ) -> ManagedGatewayGrantCredentials {
        ManagedGatewayGrantCredentials(
            grantId: "11111111-1111-1111-1111-111111111111",
            scopes: scopes,
            accessToken: accessToken,
            accessExpiresAt: accessExpiresAt,
            refreshToken: refreshToken,
            refreshExpiresAt: refreshExpiresAt,
            receivedAt: receivedAt
        )
    }

    private func grantJSON(
        access: String,
        refresh: String,
        scopes: [String] = ["polish", "ai", "agent"]
    ) -> Data {
        let encodedScopes = scopes.map { "\"\($0)\"" }.joined(separator: ",")
        return Data(
            """
            {"grantId":"11111111-1111-1111-1111-111111111111",
             "scopes":[\(encodedScopes)],"accessToken":"\(access)",
             "accessExpiresAt":"2030-01-01T00:05:00Z","refreshToken":"\(refresh)",
             "refreshExpiresAt":"2030-01-02T00:00:00Z"}
            """.utf8
        )
    }

    private func errorJSON(_ code: String) -> Data {
        Data(#"{"code":"\#(code)","message":"error","requestId":"request-id"}"#.utf8)
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
        )
    }

    private func XCTAssertThrowsManaged(
        _ expected: ManagedGatewayError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("expected \(expected)")
        } catch let error as ManagedGatewayError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

private actor MemoryGrantStore: GatewayGrantCredentialStore {
    private var credentials: ManagedGatewayGrantCredentials?

    init(_ credentials: ManagedGatewayGrantCredentials? = nil) {
        self.credentials = credentials
    }

    func load() async throws -> ManagedGatewayGrantCredentials? { credentials }
    func save(_ credentials: ManagedGatewayGrantCredentials) async throws { self.credentials = credentials }
    func delete() async throws { credentials = nil }
    func value() -> ManagedGatewayGrantCredentials? { credentials }
}

private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) { self.values = values }

    func next() -> String {
        lock.withLock { values.isEmpty ? UUID().uuidString : values.removeFirst() }
    }
}

private final class GatewayStub: @unchecked Sendable {
    struct Response {
        let status: Int
        let body: Data
        let contentType: String
        let delay: TimeInterval
        let transportError: URLError.Code?
    }

    static let shared = GatewayStub()
    private let lock = NSLock()
    private var responses: [Response] = []
    private var captured: [URLRequest] = []

    func enqueue(
        _ status: Int,
        _ body: Data,
        contentType: String = "application/json",
        delay: TimeInterval = 0,
        transportError: URLError.Code? = nil
    ) {
        lock.withLock {
            responses.append(
                Response(
                    status: status,
                    body: body,
                    contentType: contentType,
                    delay: delay,
                    transportError: transportError
                )
            )
        }
    }

    func take(_ request: URLRequest) -> Response {
        lock.withLock {
            captured.append(Self.materialize(request))
            return responses.isEmpty
                ? Response(
                    status: 500,
                    body: Data(),
                    contentType: "application/json",
                    delay: 0,
                    transportError: nil
                )
                : responses.removeFirst()
        }
    }

    func requests() -> [URLRequest] { lock.withLock { captured } }

    func reset() {
        lock.withLock {
            responses.removeAll()
            captured.removeAll()
        }
    }

    private static func materialize(_ source: URLRequest) -> URLRequest {
        var request = source
        guard request.httpBody == nil, let stream = request.httpBodyStream else { return request }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4_096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4_096)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        request.httpBody = data
        return request
    }
}

private final class GatewayURLProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = GatewayStub.shared.take(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [weak self] in
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            if let errorCode = response.transportError {
                self.client?.urlProtocol(self, didFailWithError: URLError(errorCode))
                return
            }
            let http = HTTPURLResponse(
                url: self.request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": response.contentType]
            )!
            self.client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: response.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        lock.withLock { stopped = true }
    }
}
