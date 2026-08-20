// CloudASRHTTPClientTests.swift
// OSGKeyboardTests
//
// Hermetic HTTP batch Cloud ASR clients (URLProtocol stub; no live network).

import os
@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

final class CloudASRHTTPClientTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testZhipuTranscribeDecodesTextAndIncludesHotwords() async throws {
        StubURLProtocolStorage.config = (
            200,
            Data(#"{"text":"转写结果"}"#.utf8)
        )
        let session = StubURLProtocol.makeEphemeralSession()
        let client = ZhipuCloudASRClient(
            apiKey: "sk-test",
            model: "glm-asr-2512",
            session: session
        )
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "OSGKeyboard", category: .productName, source: .manual)
        ])
        // 0.1 s @ 16 kHz
        let samples = [Float](repeating: 0.01, count: 1_600)
        let text = try await client.transcribe(
            samples: samples,
            sampleRate: 16_000,
            locale: Locale(identifier: "zh-Hans"),
            dictionary: dict
        )
        XCTAssertEqual(text, "转写结果")
        let body = try XCTUnwrap(StubURLProtocolStorage.lastRequest?.httpBody)
        // Multipart includes binary WAV — search ASCII markers in raw bytes.
        let hotwordsMarker = Data("name=\"hotwords\"".utf8)
        let termMarker = Data("OSGKeyboard".utf8)
        XCTAssertTrue(body.range(of: hotwordsMarker) != nil)
        XCTAssertTrue(body.range(of: termMarker) != nil)
    }

    func testZhipuTranscribeMaps401ToCloudASRErrorHTTP() async {
        StubURLProtocolStorage.config = (401, Data("Unauthorized".utf8))
        let session = StubURLProtocol.makeEphemeralSession()
        let client = ZhipuCloudASRClient(
            apiKey: "sk-bad",
            model: "glm-asr-2512",
            session: session
        )
        do {
            _ = try await client.transcribe(
                samples: [Float](repeating: 0, count: 1_600),
                sampleRate: 16_000,
                locale: Locale(identifier: "zh-Hans"),
                dictionary: PersonalDictionary()
            )
            XCTFail("expected http error")
        } catch let error as CloudASRError {
            guard case .http(let status, _) = error else {
                return XCTFail("expected .http, got \(error)")
            }
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testPromptCloudASRRejectsAudioLongerThan30SecondsForGroq() async {
        let session = StubURLProtocol.makeEphemeralSession()
        let client = PromptCloudASRClient(
            providerId: "groq",
            baseURL: "https://api.groq.com/openai/v1",
            apiKey: "sk-test",
            model: "whisper-large-v3-turbo",
            session: session
        )
        // 31 s @ 16 kHz — must fail before any network call.
        let samples = [Float](repeating: 0, count: 16_000 * 31)
        do {
            _ = try await client.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: Locale(identifier: "en-US"),
                dictionary: PersonalDictionary()
            )
            XCTFail("expected audioTooLong")
        } catch let error as CloudASRError {
            XCTAssertEqual(error, .audioTooLong)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertNil(StubURLProtocolStorage.lastRequest)
    }

    func testOpenRouterJsonTranscribeSendsApplicationJSON() async throws {
        StubURLProtocolStorage.config = (
            200,
            Data(#"{"text":"hello world"}"#.utf8)
        )
        let session = StubURLProtocol.makeEphemeralSession()
        let client = PromptCloudASRClient(
            providerId: "openrouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-or",
            model: "openai/whisper-large-v3-turbo",
            session: session,
            requestFormat: .openRouterJson
        )
        let text = try await client.transcribe(
            samples: [Float](repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            locale: Locale(identifier: "en-US"),
            dictionary: PersonalDictionary()
        )
        XCTAssertEqual(text, "hello world")
        let request = try XCTUnwrap(StubURLProtocolStorage.lastRequest)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertNotNil(json["input_audio"])
        XCTAssertEqual(json["model"] as? String, "openai/whisper-large-v3-turbo")
    }

    func testUnsupportedCloudASRClientThrowsProviderUnsupported() async {
        let client = UnsupportedCloudASRClient(providerId: "unknown-provider")
        do {
            _ = try await client.transcribe(
                samples: [0.1],
                sampleRate: 16_000,
                locale: Locale(identifier: "en-US"),
                dictionary: PersonalDictionary()
            )
            XCTFail("expected providerUnsupported")
        } catch let error as CloudASRError {
            XCTAssertEqual(error, .providerUnsupported)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCloudASRClientFactoryRoutesVolcengineAndLocalFallbackProviders() {
        let suite = "group.com.osgkeyboard.tests.cloud-factory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.engineMode = "cloud"
        config.asrProviderId = "volcengine"
        config.save(to: defaults)
        let store = AppGroupStore(defaults: defaults)
        XCTAssertTrue(CloudASRClientFactory.make(store: store) is VolcengineCloudASRClient)

        config.asrProviderId = "moonshot"
        config.save(to: defaults)
        let moonshotStore = AppGroupStore(defaults: defaults)
        XCTAssertTrue(
            CloudASRClientFactory.make(store: moonshotStore) is UnsupportedCloudASRClient
        )
        XCTAssertEqual(
            CloudASRModelCatalog.strategy(for: moonshotStore.asrProviderId),
            .localFallback
        )

        config.credentialSource = .managed
        config.save(to: defaults)
        let managedStore = AppGroupStore(defaults: defaults)
        XCTAssertTrue(
            CloudASRClientFactory.make(
                store: managedStore,
                managedGrants: GatewayGrantCoordinator(
                    baseURL: URL(string: "https://account.example.test")!
                )
            ) is ManagedVolcengineASRClient
        )
    }

    func testVolcengineProbeConnectionRejectsEmptyAPIKey() async {
        let client = VolcengineCloudASRClient(
            apiKey: "",
            endpoint: "",
            resourceID: CloudASRModelCatalog.volcengineDefaultResourceID,
            session: .shared
        )
        do {
            try await client.probeConnection()
            XCTFail("expected noAPIKey")
        } catch let error as CloudASRError {
            XCTAssertEqual(error, .noAPIKey)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testManagedSessionCreatesAuthorizedRequestAndStreamsBoundedPCM() async throws {
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 201, data: managedSessionDescriptor(maxFrameBytes: 4))
        ])
        let socket = FakeManagedASRWebSocket(receives: [
            .data(Data(#"{"result":{"utterances":[{"text":"你好","definite":true}]}}"#.utf8)),
            .closed(
                code: URLSessionWebSocketTask.CloseCode.normalClosure.rawValue,
                reason: "Complete"
            )
        ])
        let sockets = FakeManagedASRWebSocketFactory(socket: socket)
        let partials = LockedStrings()
        let client = managedClient(http: http, sockets: sockets)

        let live = try await client.openStreamingSession(
            locale: Locale(identifier: "zh-Hans"),
            dictionary: .empty,
            onPartial: { partials.append($0) }
        )
        // Three samples become six PCM16LE bytes and must be split 4 + 2.
        try await live.append(samples: [0, 0.5, -0.5])
        let final = try await live.finish()

        XCTAssertEqual(final, "你好")
        XCTAssertEqual(partials.values, ["你好"])
        let requests = await http.requests
        let create = try XCTUnwrap(requests.first)
        XCTAssertEqual(create.httpMethod, "POST")
        XCTAssertEqual(create.url?.path, "/v1/gateway/asr/sessions")
        XCTAssertEqual(create.value(forHTTPHeaderField: "Authorization"), "Bearer grant-token")
        XCTAssertEqual(create.value(forHTTPHeaderField: "X-Request-ID"), "request_12345678")
        let createBody = try XCTUnwrap(create.httpBody)
        let createJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: createBody) as? [String: Any]
        )
        XCTAssertEqual(createJSON["format"] as? String, "pcm")
        XCTAssertEqual(createJSON["codec"] as? String, "raw")
        XCTAssertEqual(createJSON["sampleRate"] as? Int, 16_000)
        XCTAssertEqual(createJSON["estimatedDurationMillis"] as? Int, 210_000)

        let webSocketRequest = try XCTUnwrap(sockets.request)
        XCTAssertEqual(webSocketRequest.url?.scheme, "wss")
        XCTAssertEqual(
            webSocketRequest.url?.path,
            "/v1/gateway/asr/sessions/11111111-2222-3333-4444-555555555555/stream"
        )
        XCTAssertEqual(
            webSocketRequest.value(forHTTPHeaderField: "Authorization"),
            "Bearer grant-token"
        )
        XCTAssertEqual(
            webSocketRequest.value(forHTTPHeaderField: "X-Request-ID"),
            "request_12345678"
        )
        let sent = socket.sentMessages
        XCTAssertEqual(sent.count, 3)
        guard case .data(let first) = sent[0],
              case .data(let second) = sent[1],
              case .string(let end) = sent[2] else {
            return XCTFail("expected two binary frames followed by the end control frame")
        }
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(second.count, 2)
        XCTAssertEqual(end, #"{"type":"end"}"#)
        XCTAssertTrue(socket.wasClosed)
    }

    func testManagedSessionRefreshesGrantOnceAndReusesRequestIDAfterUnauthorized() async throws {
        let unauthorized = Data(
            #"{"code":"unauthorized","message":"expired","requestId":"request_12345678"}"#.utf8
        )
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 401, data: unauthorized),
            .init(status: 201, data: managedSessionDescriptor())
        ])
        let grants = RecordingManagedASRGrantProvider(tokens: ["expired-grant", "fresh-grant"])
        let socket = FakeManagedASRWebSocket()
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: socket),
            grantProvider: grants
        )

        let live = try await client.openStreamingSession(
            locale: Locale(identifier: "zh-Hans"),
            dictionary: .empty,
            onPartial: { _ in }
        )
        live.cancel()

        let requests = await http.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer expired-grant", "Bearer fresh-grant"]
        )
        XCTAssertEqual(
            Set(requests.compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }),
            ["request_12345678"]
        )
        let refreshFlags = await grants.forceRefreshValues
        XCTAssertEqual(refreshFlags, [false, true])
    }

    func testManagedSessionMapsStableCreationFailures() async {
        let cases = [
            ManagedSessionFailureCase(
                status: 402,
                code: "insufficient_credits",
                expected: .insufficientCredits
            ),
            ManagedSessionFailureCase(
                status: 429,
                code: "asr_concurrency_limit",
                expected: .concurrencyLimit
            ),
            ManagedSessionFailureCase(
                status: 503,
                code: "provider_unavailable",
                expected: .sessionCreationFailed(
                    status: 503,
                    code: "provider_unavailable"
                )
            )
        ]

        for testCase in cases {
            let body = Data(
                #"{"code":"\#(testCase.code)","message":"ignored","requestId":"r"}"#.utf8
            )
            let http = FakeManagedASRHTTPClient(responses: [
                .init(status: testCase.status, data: body)
            ])
            let client = managedClient(
                http: http,
                sockets: FakeManagedASRWebSocketFactory(socket: FakeManagedASRWebSocket())
            )
            do {
                _ = try await client.openStreamingSession(
                    locale: Locale(identifier: "en-US"),
                    dictionary: .empty,
                    onPartial: { _ in }
                )
                XCTFail("expected \(testCase.expected)")
            } catch let error as ManagedCloudASRError {
                XCTAssertEqual(error, testCase.expected)
            } catch {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testManagedSessionConnectTimeoutIsStableAndClosesSocket() async throws {
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 201, data: managedSessionDescriptor())
        ])
        let socket = FakeManagedASRWebSocket(pingDelay: .seconds(10))
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: socket),
            connectTimeout: 0.01
        )

        do {
            _ = try await client.openStreamingSession(
                locale: Locale(identifier: "en-US"),
                dictionary: .empty,
                onPartial: { _ in }
            )
            XCTFail("expected connect timeout")
        } catch let error as ManagedCloudASRError {
            XCTAssertEqual(error, .connectTimeout)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(socket.wasClosed)
    }

    func testManagedSessionIdleTimeoutIsStable() async throws {
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 201, data: managedSessionDescriptor(idleTimeoutMillis: 10))
        ])
        let socket = FakeManagedASRWebSocket(receiveDelay: .seconds(10))
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: socket)
        )
        let live = try await client.openStreamingSession(
            locale: Locale(identifier: "en-US"),
            dictionary: .empty,
            onPartial: { _ in }
        )
        try await live.append(samples: [0.1])

        do {
            _ = try await live.finish()
            XCTFail("expected idle timeout")
        } catch let error as ManagedCloudASRError {
            XCTAssertEqual(error, .idleTimeout)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testManagedSessionMidstreamCancellationClosesAndThrowsCancellation() async throws {
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 201, data: managedSessionDescriptor())
        ])
        let socket = FakeManagedASRWebSocket(receiveDelay: .seconds(10))
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: socket)
        )
        let live = try await client.openStreamingSession(
            locale: Locale(identifier: "en-US"),
            dictionary: .empty,
            onPartial: { _ in }
        )

        live.cancel()
        do {
            try await live.append(samples: [0.1])
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // Expected: StreamingUtterancePipeline maps this to `.cancelled`.
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertTrue(socket.wasClosed)
    }

    func testManagedSessionEmptyProviderResultIsStable() async throws {
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 201, data: managedSessionDescriptor())
        ])
        let socket = FakeManagedASRWebSocket(receives: [
            .data(Data(#"{"result":{"text":""}}"#.utf8)),
            .string(#"{"type":"gateway_error","code":"asr_failed"}"#)
        ])
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: socket)
        )
        let live = try await client.openStreamingSession(
            locale: Locale(identifier: "en-US"),
            dictionary: .empty,
            onPartial: { _ in }
        )
        try await live.append(samples: [0.1])

        do {
            _ = try await live.finish()
            XCTFail("expected empty result")
        } catch let error as ManagedCloudASRError {
            XCTAssertEqual(error, .emptyResult)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testManagedBatchFallbackUsesGrantRequestIDAndParsesNDJSON() async throws {
        let payload = Data(#"""
        {"result":{"utterances":[{"text":"批量","definite":false}]}}
        {"result":{"utterances":[{"text":"批量结果","definite":true}]}}
        """#.utf8)
        let http = FakeManagedASRHTTPClient(responses: [.init(status: 200, data: payload)])
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: FakeManagedASRWebSocket())
        )

        let text = try await client.transcribe(
            samples: [Float](repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            locale: Locale(identifier: "zh-Hans"),
            dictionary: .empty
        )

        XCTAssertEqual(text, "批量结果")
        let requests = await http.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/v1/gateway/asr")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer grant-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "request_12345678")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Audio-Duration-Ms"), "100")
        XCTAssertEqual(request.httpBody?.count, 3_200)
    }

    func testManagedBatchRefreshesGrantOnceAndKeepsLogicalRequestID() async throws {
        let unauthorized = Data(
            #"{"code":"unauthorized","message":"expired","requestId":"request_12345678"}"#.utf8
        )
        let result = Data(
            #"{"result":{"utterances":[{"text":"刷新后结果","definite":true}]}}"#.utf8
        )
        let http = FakeManagedASRHTTPClient(responses: [
            .init(status: 401, data: unauthorized),
            .init(status: 200, data: result)
        ])
        let grants = RecordingManagedASRGrantProvider(tokens: ["expired-grant", "fresh-grant"])
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: FakeManagedASRWebSocket()),
            grantProvider: grants
        )

        let text = try await client.transcribe(
            samples: [Float](repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            locale: Locale(identifier: "zh-Hans"),
            dictionary: .empty
        )

        XCTAssertEqual(text, "刷新后结果")
        let requests = await http.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer expired-grant", "Bearer fresh-grant"]
        )
        XCTAssertEqual(
            Set(requests.compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }),
            ["request_12345678"]
        )
        XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        let refreshFlags = await grants.forceRefreshValues
        XCTAssertEqual(refreshFlags, [false, true])
    }

    func testManagedBatchFallbackFailureIsStable() async {
        let body = Data(
            #"{"code":"provider_unavailable","message":"ignored","requestId":"r"}"#.utf8
        )
        let http = FakeManagedASRHTTPClient(responses: [.init(status: 503, data: body)])
        let client = managedClient(
            http: http,
            sockets: FakeManagedASRWebSocketFactory(socket: FakeManagedASRWebSocket())
        )

        do {
            _ = try await client.transcribe(
                samples: [0.1],
                sampleRate: 16_000,
                locale: Locale(identifier: "en-US"),
                dictionary: .empty
            )
            XCTFail("expected batch failure")
        } catch let error as ManagedCloudASRError {
            XCTAssertEqual(
                error,
                .batchFailed(status: 503, code: "provider_unavailable")
            )
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    private func managedClient(
        http: FakeManagedASRHTTPClient,
        sockets: FakeManagedASRWebSocketFactory,
        grantProvider: any ManagedASRGrantProviding =
            StaticManagedASRGrantProvider(token: "grant-token"),
        connectTimeout: TimeInterval = 1
    ) -> ManagedVolcengineASRClient {
        ManagedVolcengineASRClient(
            baseURL: URL(string: "https://account.example.test")!,
            grantProvider: grantProvider,
            httpClient: http,
            webSocketFactory: sockets,
            connectTimeout: connectTimeout,
            requestID: { "request_12345678" }
        )
    }

    private func managedSessionDescriptor(
        maxFrameBytes: Int = 64 * 1_024,
        idleTimeoutMillis: Int = 5_000
    ) -> Data {
        Data(
            #"""
            {
              "sessionId":"11111111-2222-3333-4444-555555555555",
              "websocketPath":"/v1/gateway/asr/sessions/11111111-2222-3333-4444-555555555555/stream",
              "maxFrameBytes":\#(maxFrameBytes),
              "idleTimeoutMillis":\#(idleTimeoutMillis)
            }
            """#.utf8
        )
    }
}

private struct ManagedSessionFailureCase {
    let status: Int
    let code: String
    let expected: ManagedCloudASRError
}

private actor RecordingManagedASRGrantProvider: ManagedASRGrantProviding {
    private var tokens: [String]
    private(set) var forceRefreshValues: [Bool] = []

    init(tokens: [String]) {
        self.tokens = tokens
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        forceRefreshValues.append(forceRefresh)
        guard !tokens.isEmpty else {
            throw ManagedGatewayError.missingGrant
        }
        return tokens.removeFirst()
    }
}

private actor FakeManagedASRHTTPClient: ManagedASRHTTPClient {
    struct Response: Sendable {
        let status: Int
        let data: Data
    }

    private var queued: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [Response]) {
        queued = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !queued.isEmpty else {
            throw URLError(.badServerResponse)
        }
        let response = queued.removeFirst()
        let http = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response.data, http)
    }
}

private final class FakeManagedASRWebSocketFactory:
    ManagedASRWebSocketFactory, @unchecked Sendable {
    private let socket: FakeManagedASRWebSocket
    private let lock = OSAllocatedUnfairLock(initialState: Optional<URLRequest>.none)

    var request: URLRequest? {
        lock.withLock { $0 }
    }

    init(socket: FakeManagedASRWebSocket) {
        self.socket = socket
    }

    func makeWebSocket(for request: URLRequest) -> any ManagedASRWebSocket {
        lock.withLock { $0 = request }
        return socket
    }
}

private final class FakeManagedASRWebSocket: ManagedASRWebSocket, @unchecked Sendable {
    private struct State {
        var receives: [ManagedASRWebSocketMessage]
        var sent: [ManagedASRWebSocketMessage] = []
        var resumed = false
        var closed = false
    }

    private let lock: OSAllocatedUnfairLock<State>
    private let pingDelay: Duration?
    private let receiveDelay: Duration?

    var sentMessages: [ManagedASRWebSocketMessage] {
        lock.withLock { $0.sent }
    }

    var wasClosed: Bool {
        lock.withLock { $0.closed }
    }

    init(
        receives: [ManagedASRWebSocketMessage] = [],
        pingDelay: Duration? = nil,
        receiveDelay: Duration? = nil
    ) {
        lock = OSAllocatedUnfairLock(initialState: State(receives: receives))
        self.pingDelay = pingDelay
        self.receiveDelay = receiveDelay
    }

    func resume() {
        lock.withLock { $0.resumed = true }
    }

    func ping() async throws {
        if let pingDelay {
            try await Task.sleep(for: pingDelay)
        }
    }

    func send(_ message: ManagedASRWebSocketMessage) async throws {
        if lock.withLock({ $0.closed }) {
            throw URLError(.cancelled)
        }
        lock.withLock { $0.sent.append(message) }
    }

    func receive() async throws -> ManagedASRWebSocketMessage {
        if let receiveDelay {
            try await Task.sleep(for: receiveDelay)
        }
        if let next = lock.withLock({ state -> ManagedASRWebSocketMessage? in
            guard !state.receives.isEmpty else { return nil }
            return state.receives.removeFirst()
        }) {
            return next
        }
        try await Task.sleep(for: .seconds(10))
        throw URLError(.timedOut)
    }

    func close() {
        lock.withLock { $0.closed = true }
    }
}

private final class LockedStrings: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())

    var values: [String] {
        lock.withLock { $0 }
    }

    func append(_ value: String) {
        lock.withLock { $0.append(value) }
    }
}
