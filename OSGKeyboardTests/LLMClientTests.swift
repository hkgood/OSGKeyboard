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
        Keychain.resetTestMemoryStore()
        try? Keychain.deleteAPIKey()
        try? Keychain.deleteLegacyAPIKey()
        try? Keychain.deleteAPIKey(for: "qwen")
        try? Keychain.deleteAPIKey(for: "openai")
        try? Keychain.deleteAPIKey(for: "deepseek")
        StubURLProtocolStorage.config = nil
        StubURLProtocolStorage.delaySeconds = 0
        StubURLProtocolStorage.lastRequest = nil
    }

    override func tearDownWithError() throws {
        try? Keychain.deleteAPIKey()
        try? Keychain.deleteLegacyAPIKey()
        try? Keychain.deleteAPIKey(for: "qwen")
        try? Keychain.deleteAPIKey(for: "openai")
        try? Keychain.deleteAPIKey(for: "deepseek")
        Keychain.resetTestMemoryStore()
        StubURLProtocolStorage.config = nil
        StubURLProtocolStorage.delaySeconds = 0
        StubURLProtocolStorage.lastRequest = nil
    }

    // MARK: - ProviderConfig persistence

    func testProviderConfigPersistsAcrossInstances() {
        let suiteName = "group.com.osgkeyboard.shared.tests.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

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

    /// Local ASR needs no cloud ASR key, but polish still requires a user API key.
    func testLocalEngineWithoutAPIKeyIsNotPolishConfigured() {
        let suiteName = "group.com.osgkeyboard.shared.tests.isconfigured.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = ProviderConfig(defaults: defaults)
        config.engineMode = "cloud"
        XCTAssertFalse(config.isConfigured)
        config.engineMode = "local"
        XCTAssertFalse(config.isPolishConfigured)
        XCTAssertFalse(config.isConfigured)
        config.engineMode = "cloud"
        XCTAssertFalse(config.isConfigured)
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

    func testPolishRequestUsesConservativeGenerationParameters() async throws {
        let request = LLMRequest(
            model: "test-model",
            messages: [.system("brief"), .user("hello")],
            temperature: 0.1,
            maxTokens: LLMRequest.outputTokenLimit(for: "hello"),
            topP: 0.9
        )
        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(body["temperature"] as? Double, 0.1)
        XCTAssertEqual(body["top_p"] as? Double, 0.9)
        XCTAssertEqual(body["max_tokens"] as? Int, 256)
    }

    func testLLMResponseDecodesCachedPromptUsage() throws {
        let data = """
        {
          "choices": [{"index":0,"message":{"role":"assistant","content":"ok"}}],
          "usage": {
            "prompt_tokens": 1000,
            "prompt_tokens_details": {"cached_tokens": 800}
          }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(LLMResponse.self, from: data)
        XCTAssertEqual(response.usage?.promptTokens, 1_000)
        XCTAssertEqual(response.usage?.cachedTokens, 800)
    }

    func testCacheMetricsRoundTrip() {
        let suite = "group.com.osgkeyboard.shared.tests.cache.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        LLMCacheMetricsStore.record(
            providerId: "openai",
            promptTokens: 1_000,
            cachedTokens: 800,
            defaults: defaults
        )
        XCTAssertEqual(
            LLMCacheMetricsStore.latest(defaults: defaults)?.summary,
            "800/1000 80% (openai)"
        )
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
    /// be readable through `AppGroupStore` on the same suite.
    func testAppGroupCrossProcessLegacyOffModeMigratesToPolish() async {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Writer side: ProviderConfig (main App) writes API key + legacy off mode.
        let config = ProviderConfig(defaults: defaults)
        config.engineMode = "cloud"
        config.apiKey = "sk-test-1234"
        config.model = "gpt-4o-mini"
        config.baseURL = "https://example.com/v1"
        config.modeId = "off"

        // Reader side: AppGroupStore (keyboard extension) reads from the
        // same suite. Cloud loads remaps legacy off → polish.
        let store = AppGroupStore(defaults: defaults)
        XCTAssertEqual(store.apiKey, "sk-test-1234", "API key did not survive the cross-process boundary")
        XCTAssertEqual(store.modeId, "polish", "legacy off mode migrates to polish")
        XCTAssertEqual(store.model, "gpt-4o-mini")
    }

    func testAppGroupStoreNoAPIKeySurfacesAsLLMError() async {
        // Mirror what PolishingService does internally: construct a
        // client via AppGroupStore with an empty key, expect noAPIKey.
        // (PolishingService itself lives in the keyboard extension target
        // and isn't @testable-importable from this test target, so we
        // exercise the same path one layer down.)
        Keychain.resetTestMemoryStore()
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Avoid default deepseek + empty baseURL accidentally using a leftover
        // Keychain entry; pin openai with an empty key on this suite.
        defaults.set("openai", forKey: "config.providerId")
        let store = AppGroupStore(defaults: defaults)
        XCTAssertTrue(store.apiKey.isEmpty)
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

    // MARK: - TEST-2: cloud always polishes (legacy modeId ignored)

    /// Cloud engine must invoke the LLM even when a legacy `modeId == "off"`
    /// value is still present in the App Group suite.
    func testPolisherPolishesWhenCloudEvenIfModeOffLegacy() async throws {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("off", forKey: "config.modeId")
        defaults.set("cloud", forKey: "config.engineMode")
        defaults.set("https://example.com/v1", forKey: "config.baseURL")
        defaults.set("sk-test", forKey: "config.apiKey")
        defaults.set("gpt-4o-mini", forKey: "config.model")

        let counter = CallCounter()
        let countingClient = CountingLLMClient(counter: counter) { raw, _ in
            "POLISHED: \(raw)"
        }

        let store = AppGroupStore(defaults: defaults)
        let polisher = PolishingService(
            store: store,
            client: countingClient,
            timeout: 1
        )

        let result = try await polisher.polish("  hello world  ")
        XCTAssertEqual(result, "POLISHED: hello world")
        let calls = await counter.value()
        XCTAssertEqual(calls, 1, "cloud engine must polish even with legacy modeId=off")
    }

    /// Local engine still runs the polish LLM step when a client is injected.
    func testPolisherInvokesLLMWhenEngineLocal() async throws {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("local", forKey: "config.engineMode")
        defaults.set("polish", forKey: "config.modeId")

        let counter = CallCounter()
        let countingClient = CountingLLMClient(counter: counter) { raw, _ in
            "POLISHED: \(raw)"
        }

        let store = AppGroupStore(defaults: defaults)
        let polisher = PolishingService(
            store: store,
            client: countingClient,
            timeout: 1
        )

        let result = try await polisher.polish("hello world")
        XCTAssertEqual(result, "POLISHED: hello world")
        let calls = await counter.value()
        XCTAssertEqual(calls, 1, "local engine must always invoke the polish LLM step")
    }

    /// Local engine pins DeepSeek — cloud-provider URL/model in App Group
    /// must not leak into the LLM request (regression: Qwen URL + DeepSeek key → 401).
    func testLLMClientFactoryRoutesAnthropic() {
        let client = LLMClientFactory.make(
            providerId: "anthropic",
            baseURL: "",
            apiKey: "sk-test",
            model: "claude-sonnet-4-6"
        )
        XCTAssertTrue(client is AnthropicMessagesClient)
    }

    func testLLMClientFactoryResolvesGeminiOpenAICompatBaseURL() {
        let client = LLMClientFactory.make(
            providerId: "gemini",
            baseURL: "",
            apiKey: "key",
            model: "gemini-2.5-flash"
        ) as! OpenAICompatibleClient
        XCTAssertEqual(
            client.baseURL,
            "https://generativelanguage.googleapis.com/v1beta/openai"
        )
    }

    /// DeepSeek V4 thinking defaults ON server-side; polish must explicitly disable it.
    func testDeepSeekPolishDisablesThinkingByDefault() {
        var body: [String: Any] = ["model": "deepseek-v4-flash"]
        LLMThinkingControl.apply(
            to: &body,
            providerId: "deepseek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-v4-flash",
            enabled: false
        )
        let thinking = body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "disabled")
        XCTAssertNil(body["reasoning_effort"], "disabled path must not send reasoning_effort (low→high on DeepSeek)")
    }

    func testDeepSeekPolishEnablesThinkingWhenToggledOn() {
        var body: [String: Any] = ["model": "deepseek-v4-flash"]
        LLMThinkingControl.apply(
            to: &body,
            providerId: "deepseek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-v4-flash",
            enabled: true
        )
        let thinking = body["thinking"] as? [String: Any]
        XCTAssertEqual(thinking?["type"] as? String, "enabled")
        XCTAssertEqual(body["reasoning_effort"] as? String, "high")
    }

    /// Ordinary OpenAI chat models must not get thinking fields when the toggle is off.
    func testOpenAIChatDoesNotInjectThinkingWhenDisabled() {
        var body: [String: Any] = ["model": "gpt-4o-mini"]
        LLMThinkingControl.apply(
            to: &body,
            providerId: "openai",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            enabled: false
        )
        XCTAssertNil(body["thinking"])
        XCTAssertNil(body["reasoning_effort"])
        XCTAssertNil(body["thinking_config"])
    }

    func testLLMThinkingDefaultIsOffInFreshConfiguration() {
        let suiteName = "group.com.osgkeyboard.shared.tests.thinking.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = ProviderConfig(defaults: defaults)
        XCTAssertFalse(config.llmThinkingEnabled, "cloud polish thinking must default off")
    }

    func testResolveLLMEndpointUsesPresetWhenProviderPinned() {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("qwen", forKey: "config.providerId")
        defaults.set(
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            forKey: "config.baseURL"
        )
        defaults.set("qwen-plus", forKey: "config.model")

        let store = AppGroupStore(defaults: defaults)
        let deepseekPreset = LLMProvider.provider(id: "deepseek")
        let pinned = PolishingService.resolveLLMEndpoint(
            store: store,
            preset: deepseekPreset,
            providerIdOverride: "deepseek"
        )
        XCTAssertEqual(pinned.baseURL, deepseekPreset.defaultBaseURL)
        XCTAssertEqual(pinned.model, deepseekPreset.defaultModel)

        let qwenPreset = LLMProvider.provider(id: "qwen")
        let cloud = PolishingService.resolveLLMEndpoint(
            store: store,
            preset: qwenPreset,
            providerIdOverride: nil
        )
        XCTAssertEqual(
            cloud.baseURL,
            "https://dashscope.aliyuncs.com/compatible-mode/v1",
            "cloud engine must keep user base URL"
        )
        XCTAssertEqual(cloud.model, "qwen-plus", "cloud engine must keep user model")
    }

    func testTranslationChipVisibleWithoutTargetLocale() {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("cloud", forKey: "config.engineMode")
        defaults.set(TranslationLanguageCatalog.offLocaleId, forKey: "config.translationTargetLocaleId")
        let cloudStore = AppGroupStore(defaults: defaults)
        XCTAssertTrue(cloudStore.isTranslationChipVisible)
        XCTAssertFalse(cloudStore.isTranslationEffective)

        defaults.set("local", forKey: "config.engineMode")
        defaults.set(TranslationLanguageCatalog.offLocaleId, forKey: "config.translationTargetLocaleId")
        let localStore = AppGroupStore(defaults: defaults)
        XCTAssertTrue(localStore.isTranslationChipVisible)
        XCTAssertFalse(localStore.isTranslationEffective)
    }

    /// Local engine always runs the LLM step when translation is armed.
    func testPolisherTranslatesWhenLocalEngineTranslationEnabled() async throws {
        let suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("local", forKey: "config.engineMode")
        defaults.set("en", forKey: "config.translationTargetLocaleId")

        let counter = CallCounter()
        let countingClient = CountingLLMClient(counter: counter) { raw, prompt in
            XCTAssertEqual(raw, "你好")
            XCTAssertTrue(prompt.contains("English"), "translate prompt should target English")
            return "Hello"
        }

        let store = AppGroupStore(defaults: defaults)
        let polisher = PolishingService(
            store: store,
            client: countingClient,
            timeout: 1
        )

        let result = try await polisher.polish(
            "  你好  ",
            mode: .translate(targetLocaleId: "en"),
            providerIdOverride: "deepseek"
        )
        XCTAssertEqual(result, "Hello")
        let calls = await counter.value()
        XCTAssertEqual(calls, 1)
    }

    func testTranslationPromptIncludesAppContextGuideline() {
        let prompt = TranslationPrompt.make(
            target: TranslationLanguageCatalog.resolve("en"),
            providerId: "openai",
            appContext: .code
        )
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("preserve English identifiers"))
    }

    func testTranslationPromptIncludesStructureContract() {
        let english = TranslationPrompt.make(
            target: TranslationLanguageCatalog.resolve("en"),
            providerId: "openai",
            appContext: .document,
            sourceText: "hello world"
        )
        XCTAssertTrue(english.localizedCaseInsensitiveContains("Hard structure rules"))
        XCTAssertTrue(english.localizedCaseInsensitiveContains("CORRECT"))
        XCTAssertTrue(english.localizedCaseInsensitiveContains("1. Fix the login crash"))
        XCTAssertTrue(english.localizedCaseInsensitiveContains("numbered list"))

        let chinese = TranslationPrompt.make(
            target: TranslationLanguageCatalog.resolve("en"),
            providerId: "deepseek",
            appContext: .document,
            sourceText: "你好世界这是一段中文口述"
        )
        XCTAssertTrue(chinese.contains("结构硬规则"))
        XCTAssertTrue(chinese.contains("正确"))
        XCTAssertTrue(chinese.contains("1. Fix the login crash"))
        XCTAssertTrue(chinese.contains("编号列表"))
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

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        await counter.bump()
        return try await body(text, systemPrompt)
    }
}
