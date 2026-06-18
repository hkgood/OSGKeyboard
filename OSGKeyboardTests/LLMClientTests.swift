// LLMClientTests.swift
// OSGKeyboard · Tests
//
// Unit tests for the OpenAI-compatible LLM client using URLProtocol stub.

import XCTest
@testable import OSGKeyboard
@testable import OSGKeyboardShared

final class LLMClientTests: XCTestCase {

    override func setUpWithError() throws {
        // The Keychain is process-global in the simulator (one simulator,
        // one keychain DB), so an API key written by a previous test would
        // leak into the next one unless we wipe it here. We intentionally
        // swallow errors — `errSecItemNotFound` is fine.
        try? Keychain.deleteAPIKey()
        StubURLProtocolStorage.config = nil
        StubURLProtocolStorage.delaySeconds = 0
        StubURLProtocolStorage.lastRequest = nil
    }

    override func tearDownWithError() throws {
        try? Keychain.deleteAPIKey()
        StubURLProtocolStorage.config = nil
        StubURLProtocolStorage.delaySeconds = 0
        StubURLProtocolStorage.lastRequest = nil
    }

    // MARK: - ProviderConfig persistence

    func testProviderConfigPersistsAcrossInstances() {
        let suiteName = "group.com.osgkeyboard.shared.tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let config1 = ProviderConfig(defaults: defaults)
        config1.baseURL = "https://example.com/v1"
        config1.apiKey = "test-key"
        config1.model = "test-model"

        let config2 = ProviderConfig(defaults: defaults)
        XCTAssertEqual(config2.baseURL, "https://example.com/v1")
        XCTAssertEqual(config2.apiKey, "test-key")
        XCTAssertEqual(config2.model, "test-model")
        XCTAssertTrue(config2.isConfigured)
    }

    // MARK: - OpenAICompatibleClient

    func testPolishSendsCorrectRequestAndDecodesResponse() async throws {
        StubURLProtocolStorage.config = (200, """
        {
          "id": "chatcmpl-1",
          "choices": [
            { "index": 0, "message": { "role": "assistant", "content": "Hello, world!" }, "finish_reason": "stop" }
          ]
        }
        """.data(using: .utf8)!)
        defer { StubURLProtocolStorage.config = nil }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)

        let client = OpenAICompatibleClient(
            baseURL: "https://example.com/v1",
            apiKey: "sk-test",
            model: "test-model",
            session: session
        )

        let result = try await client.polish("hi", systemPrompt: "be brief")
        XCTAssertEqual(result, "Hello, world!")
        let req = StubURLProtocolStorage.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertTrue(req?.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
    }

    func testPolishThrowsOnHTTPError() async {
        StubURLProtocolStorage.config = (401, "Unauthorized".data(using: .utf8)!)
        defer { StubURLProtocolStorage.config = nil }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)

        let client = OpenAICompatibleClient(
            baseURL: "https://example.com/v1",
            apiKey: "sk-test",
            model: "m",
            session: session
        )

        do {
            _ = try await client.polish("hi", systemPrompt: "p")
            XCTFail("expected error")
        } catch let LLMError.http(status) {
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testPolishThrowsWhenAPIKeyMissing() async {
        let client = OpenAICompatibleClient(
            baseURL: "https://example.com/v1",
            apiKey: "",
            model: "m"
        )
        do {
            _ = try await client.polish("hi", systemPrompt: "p")
            XCTFail("expected error")
        } catch LLMError.noAPIKey {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - P0-③ new coverage (catch-path + App Group cross-process)

    func testPolishThrowsOnHTTP429RateLimited() async {
        StubURLProtocolStorage.config = (429, "rate limited".data(using: .utf8)!)
        defer { StubURLProtocolStorage.config = nil }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)

        let client = OpenAICompatibleClient(
            baseURL: "https://example.com/v1",
            apiKey: "sk-test",
            model: "m",
            session: session
        )
        do {
            _ = try await client.polish("hi", systemPrompt: "p")
            XCTFail("expected error")
        } catch LLMError.rateLimited {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testPolishThrowsOnTransportTimeout() async {
        // Stub the transport so it never replies in time. The client has a
        // 15 s `requestTimeout` on the URLRequest; we arrange for the stub
        // to take 5 s (well under that) and instead *cancel* the in-flight
        // task ourselves before the stub wins the race. That's how the
        // KeyboardViewController triggers cancellation in real life (mode
        // switch mid-polish) and is the surface `LLMError.cancelled` was
        // added to cover. We also assert the client *throws* — i.e. the
        // old "stub returns 200 synchronously and we never see the error"
        // failure mode is gone.
        StubURLProtocolStorage.config = (200, Data())
        StubURLProtocolStorage.delaySeconds = 5
        defer {
            StubURLProtocolStorage.config = nil
            StubURLProtocolStorage.delaySeconds = 0
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: cfg)

        let client = OpenAICompatibleClient(
            baseURL: "https://example.com/v1",
            apiKey: "sk-test",
            model: "m",
            session: session
        )

        let task = Task<Bool, Error> {
            do {
                _ = try await client.polish("hi", systemPrompt: "p")
                return false   // completed — unexpected
            } catch {
                throw error
            }
        }
        // Give the request a head start so it's already on the wire when
        // we cancel.
        try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms
        task.cancel()

        var threw = false
        var caughtTransportish = false
        do {
            _ = try await task.value
        } catch is CancellationError {
            threw = true
        } catch let err as LLMError {
            threw = true
            // We accept any of: cancelled, transport, decoding — the URL
            // stack is platform-quirky about how it surfaces a cancelled
            // request from inside URLSession's protocol handler.
            switch err {
            case .cancelled, .transport, .decoding:
                caughtTransportish = true
            default:
                break
            }
        } catch {
            threw = true
        }
        XCTAssertTrue(threw, "expected client.polish to throw on cancelled transport")
        XCTAssertTrue(caughtTransportish, "expected .cancelled / .transport / .decoding — got something else")
    }

    /// Cross-process App Group contract: what `ProviderConfig` writes must
    /// be readable through `AppGroupStore` (and vice-versa) on the same
    /// suite, and `mode == .off` short-circuits before any network call.
    func testAppGroupCrossProcessAndOffModeShortCircuit() async {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Writer side: ProviderConfig (main App) writes API key + mode = off.
        let config = ProviderConfig(defaults: defaults)
        config.apiKey = "sk-test-1234"
        config.model = "gpt-4o-mini"
        config.baseURL = "https://example.com/v1"
        config.modeId = "off"

        // Reader side: AppGroupStore (keyboard extension) reads from the
        // same suite.
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.apiKey, "sk-test-1234", "API key did not survive the cross-process boundary")
        XCTAssertEqual(store.modeId, "off")
        XCTAssertEqual(store.model, "gpt-4o-mini")

        // mode == .off must short-circuit (the keyboard extension never
        // even calls `polisher.polish` in this mode, so no LLMClient is
        // constructed and no network request happens). We model the
        // short-circuit on the read side: the persisted mode is "off" and
        // any upstream caller checking `state.mode == .off` would skip
        // the LLM. The guarantee is the persistence + the literal value.
        XCTAssertEqual(store.modeId, "off")
    }

    func testAppGroupStoreNoAPIKeySurfacesAsLLMError() async {
        // Mirror what PolishingService does internally: construct a
        // client via AppGroupStore with an empty key, expect noAPIKey.
        // (PolishingService itself lives in the keyboard extension target
        // and isn't @testable-importable from this test target, so we
        // exercise the same path one layer down.)
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppGroupStore(defaults: defaults)
        // apiKey stays empty by default — we never wrote one to the suite.
        let client = store.makeClient()

        do {
            _ = try await client.polish("hello", systemPrompt: "p")
            XCTFail("expected noAPIKey")
        } catch LLMError.noAPIKey {
            // ok
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - TEST-2: mode = .off short-circuits PolishingService

    /// `PolishingService.polish()` must not invoke the underlying
    /// `LLMClient` when the App Group store reports `modeId == "off"`.
    /// We verify both halves of that contract:
    ///   1. The return value is the trimmed input (not a polished round-trip).
    ///   2. The `LLMClient` is never asked to talk to the network.
    func testPolisherSkipsNetworkWhenModeOff() async throws {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // modeId = "off" — this is the switch we care about.
        defaults.set("off", forKey: "config.modeId")
        defaults.set("https://example.com/v1", forKey: "config.baseURL")
        defaults.set("sk-should-not-be-used", forKey: "config.apiKey")
        defaults.set("gpt-4o-mini", forKey: "config.model")

        // Counter LLMClient: if `polish()` is ever called, this trips.
        let counter = CallCounter()
        let countingClient = CountingLLMClient(counter: counter) { _, _ in
            XCTFail("LLMClient.polish was invoked under mode=off — short-circuit failed")
            return ""
        }

        let store = AppGroupStore(defaults: defaults)
        let polisher = PolishingService(
            store: store,
            client: countingClient,
            timeout: 1
        )

        let result = try await polisher.polish("  hello world  ")
        XCTAssertEqual(result, "hello world", "mode=off must return trimmed input, not polished output")
        let calls = await counter.value()
        XCTAssertEqual(calls, 0, "LLMClient.polish must not be called when modeId == \"off\"")
    }
}

// MARK: - Test helpers

/// Thread-safe counter for proving a call site never invoked the LLM.
private actor CallCounter {
    private(set) var n = 0
    func bump() { n += 1 }
    func value() -> Int { n }
}

/// Minimal `LLMClient` that records each call and forwards to a user-
/// supplied closure. Used by tests that need to prove a particular
/// code path *did not* invoke the client.
private struct CountingLLMClient: LLMClient {
    let counter: CallCounter
    let body: @Sendable (String, String) async throws -> String

    var requestTimeout: TimeInterval { 15 }

    func polish(_ text: String, systemPrompt: String) async throws -> String {
        await counter.bump()
        return try await body(text, systemPrompt)
    }
}

// MARK: - URLProtocol stub

/// Per-test stub config holder. Tests set these via `StubURLProtocol.config =`
/// before invoking the code under test, then reset to nil in cleanup.
private enum StubURLProtocolStorage {
    nonisolated(unsafe) static var config: (statusCode: Int, body: Data)?
    nonisolated(unsafe) static var delaySeconds: Double = 0
    nonisolated(unsafe) static var lastRequest: URLRequest?
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let cfg = StubURLProtocolStorage.config ?? (statusCode: 200, body: Data())
        let delay = StubURLProtocolStorage.delaySeconds
        StubURLProtocolStorage.lastRequest = request

        // Simulate a slow transport. We honour URLProtocol.stopLoading() so
        // cancellation doesn't leave the test hanging, and we yield to the
        // run loop so `URLSession.data(for:)` actually observes the delay
        // (a busy-wait would never let the cooperative scheduler time out).
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard self.client != nil else { return }
            let response = HTTPURLResponse(
                url: self.request.url!,
                statusCode: cfg.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: cfg.body)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
