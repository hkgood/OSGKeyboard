// LLMClientTests.swift
// OSGKeyboard · Tests
//
// Unit tests for the OpenAI-compatible LLM client using URLProtocol stub.

import XCTest
@testable import OSGKeyboard
@testable import OSGKeyboardShared

final class LLMClientTests: XCTestCase {

    // MARK: - ProviderConfig persistence

    func testProviderConfigPersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "group.com.osgkeyboard.ios.tests")!
        defaults.removePersistentDomain(forName: "group.com.osgkeyboard.ios.tests")

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
        } catch let LLMError.http(status, _) {
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
}

// MARK: - URLProtocol stub

/// Per-test stub config holder. Tests set these via `StubURLProtocol.config =`
/// before invoking the code under test, then reset to nil in cleanup.
private enum StubURLProtocolStorage {
    nonisolated(unsafe) static var config: (statusCode: Int, body: Data)?
    nonisolated(unsafe) static var lastRequest: URLRequest?
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let cfg = StubURLProtocolStorage.config ?? (statusCode: 200, body: Data())
        StubURLProtocolStorage.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: cfg.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: cfg.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
