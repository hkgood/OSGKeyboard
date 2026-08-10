// AIModeLLMClientTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class AIModeLLMClientTests: XCTestCase {

    func testDeepSeekFlashSupportsResponsesSearch() {
        XCTAssertTrue(AIModeSearchSupport.deepSeekSupportsResponsesSearch(model: "deepseek-v4-flash"))
        XCTAssertTrue(AIModeSearchSupport.deepSeekSupportsResponsesSearch(model: "deepseek-v4-flash-0731"))
        XCTAssertFalse(AIModeSearchSupport.deepSeekSupportsResponsesSearch(model: "deepseek-v4-pro"))
        XCTAssertFalse(AIModeSearchSupport.deepSeekSupportsResponsesSearch(model: "deepseek-chat"))
    }

    func testResponsesURLAppendsPath() {
        XCTAssertEqual(
            ResponsesAPILLMClient.responsesURL(from: "https://api.openai.com/v1")?.absoluteString,
            "https://api.openai.com/v1/responses"
        )
        XCTAssertEqual(
            ResponsesAPILLMClient.responsesURL(from: "https://api.deepseek.com/v1/")?.absoluteString,
            "https://api.deepseek.com/v1/responses"
        )
    }

    func testParseResponsesOutputTextField() throws {
        let json = """
        {"output_text":"Hello from search","output":[]}
        """.data(using: .utf8)!
        XCTAssertEqual(try ResponsesAPILLMClient.parseOutputText(from: json), "Hello from search")
    }

    func testParseResponsesMessageContentParts() throws {
        let json = """
        {
          "output": [
            {"type":"reasoning","content":[{"type":"reasoning_text","text":"think"}]},
            {"type":"message","content":[
              {"type":"output_text","text":"Part A"},
              {"type":"output_text","text":" Part B"}
            ]}
          ]
        }
        """.data(using: .utf8)!
        XCTAssertEqual(try ResponsesAPILLMClient.parseOutputText(from: json), "Part A Part B")
    }

    func testFactoryUsesSearchFallbackForDeepSeekFlash() {
        let client = AIModeLLMClientFactory.make(
            providerId: "deepseek",
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "sk-test",
            model: "deepseek-v4-flash"
        )
        XCTAssertTrue(client is AIModeSearchFallbackClient)
    }

    func testFactorySkipsSearchForDeepSeekPro() {
        let client = AIModeLLMClientFactory.make(
            providerId: "deepseek",
            baseURL: "https://api.deepseek.com/v1",
            apiKey: "sk-test",
            model: "deepseek-v4-pro"
        )
        XCTAssertFalse(client is AIModeSearchFallbackClient)
        XCTAssertTrue(client is OpenAICompatibleClient)
    }

    func testFactoryUsesSearchFallbackForOpenAI() {
        let client = AIModeLLMClientFactory.make(
            providerId: "openai",
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-test",
            model: "gpt-5.4-mini"
        )
        XCTAssertTrue(client is AIModeSearchFallbackClient)
    }

    func testFactoryPlainForGroq() {
        let client = AIModeLLMClientFactory.make(
            providerId: "groq",
            baseURL: "https://api.groq.com/openai/v1",
            apiKey: "gsk-test",
            model: "llama-3.3-70b-versatile"
        )
        XCTAssertFalse(client is AIModeSearchFallbackClient)
    }

    func testOpenAIDefaultModelSupportsSearchPreset() {
        let openai = LLMProvider.provider(id: "openai")
        XCTAssertEqual(openai.defaultModel, "gpt-5.4-mini")
    }

    func testUpdatedProviderDefaultModels() {
        XCTAssertEqual(LLMProvider.provider(id: "qwen").defaultModel, "qwen-plus-latest")
        XCTAssertEqual(LLMProvider.provider(id: "zhipu").defaultModel, "glm-4.7-flash")
        XCTAssertEqual(LLMProvider.provider(id: "moonshot").defaultModel, "kimi-k2.5")
        XCTAssertEqual(LLMProvider.provider(id: "xai").defaultModel, "grok-4-fast-reasoning")
        XCTAssertEqual(LLMProvider.provider(id: "gemini").defaultModel, "gemini-3.1-flash-lite")
        XCTAssertEqual(LLMProvider.provider(id: "minimax").defaultModel, "MiniMax-M2.7")
        XCTAssertEqual(LLMProvider.provider(id: "anthropic").defaultModel, "claude-sonnet-4-6")
        XCTAssertEqual(LLMProvider.provider(id: "siliconflow").defaultModel, "Qwen/Qwen3-8B-Instruct")
        XCTAssertEqual(LLMProvider.provider(id: "openrouter").defaultModel, "qwen/qwen3-8b:free")
        XCTAssertEqual(LLMProvider.provider(id: "cometapi").defaultModel, "gpt-5.4-mini")
        XCTAssertEqual(LLMProvider.provider(id: "codingPlanX").defaultModel, "gpt-5.4-mini")
    }

    func testPolishAndAIModeResolveIdenticalEndpointFromSettings() {
        let suiteName = "group.com.osgkeyboard.shared.tests.aimode.endpoint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("openai", forKey: AppGroupConfiguration.Keys.providerId)
        defaults.set("https://api.openai.com/v1", forKey: AppGroupConfiguration.Keys.baseURL)
        defaults.set("gpt-5.4-mini", forKey: AppGroupConfiguration.Keys.model)

        let store = AppGroupStore(defaults: defaults)
        let providerID = PolishingService.resolvedProviderId(store: store, providerIdOverride: nil)
        let preset = LLMProvider.provider(id: providerID)
        let polishEndpoint = PolishingService.resolveLLMEndpoint(
            store: store,
            preset: preset,
            providerIdOverride: nil
        )
        // AI mode must not invent a different model — Settings model wins.
        let aiEndpoint = PolishingService.resolveLLMEndpoint(
            store: store,
            preset: preset,
            providerIdOverride: nil
        )
        XCTAssertEqual(providerID, "openai")
        XCTAssertEqual(polishEndpoint.model, "gpt-5.4-mini")
        XCTAssertEqual(aiEndpoint.model, polishEndpoint.model)
        XCTAssertEqual(aiEndpoint.baseURL, polishEndpoint.baseURL)
    }

    func testEmptyStoreModelFallsBackToPresetDefaultForBothModes() {
        let suiteName = "group.com.osgkeyboard.shared.tests.aimode.defaultmodel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("moonshot", forKey: AppGroupConfiguration.Keys.providerId)
        defaults.set("", forKey: AppGroupConfiguration.Keys.model)

        let store = AppGroupStore(defaults: defaults)
        let preset = LLMProvider.provider(id: "moonshot")
        let endpoint = PolishingService.resolveLLMEndpoint(
            store: store,
            preset: preset,
            providerIdOverride: nil
        )
        XCTAssertEqual(endpoint.model, "kimi-k2.5")
    }

    func testChatCompletionsStreamDeltaIgnoresReasoningContent() {
        let json = """
        {"choices":[{"delta":{"reasoning_content":"think","content":"可见"}}]}
        """.data(using: .utf8)!
        XCTAssertEqual(LLMStreamDeltaParser.chatCompletionsDelta(from: json), "可见")
    }

    func testResponsesStreamDeltaOnlyOutputText() {
        let delta = """
        {"type":"response.output_text.delta","delta":"Hello"}
        """.data(using: .utf8)!
        XCTAssertEqual(LLMStreamDeltaParser.responsesOutputTextDelta(from: delta), "Hello")

        let reasoning = """
        {"type":"response.reasoning_text.delta","delta":"secret"}
        """.data(using: .utf8)!
        XCTAssertNil(LLMStreamDeltaParser.responsesOutputTextDelta(from: reasoning))
    }

    func testAnthropicStreamDeltaSkipsThinking() {
        let text = """
        {"type":"content_block_delta","delta":{"type":"text_delta","text":"答"}}
        """.data(using: .utf8)!
        XCTAssertEqual(LLMStreamDeltaParser.anthropicTextDelta(from: text), "答")

        let thinking = """
        {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"…"}}
        """.data(using: .utf8)!
        XCTAssertNil(LLMStreamDeltaParser.anthropicTextDelta(from: thinking))
    }

    func testSSEDataPayloadParsing() {
        XCTAssertEqual(
            LLMStreamTransport.sseDataPayload(from: "data: {\"a\":1}"),
            Data("{\"a\":1}".utf8)
        )
        XCTAssertNil(LLMStreamTransport.sseDataPayload(from: "event: message"))
        XCTAssertNil(LLMStreamTransport.sseDataPayload(from: ": keep-alive"))
    }

    /// Regression: UTF-8 Chinese in SSE must not be decoded byte-as-character
    /// (that produced Latin-1 mojibake like "ä»å¤©…" for weather answers).
    func testSSEBodyPreservesChineseUTF8Content() throws {
        let answer = "今天北京多云间晴，最高气温33℃，夜间有分散性雷阵雨，最低气温25℃。"
        let chunkJSON: [String: Any] = [
            "choices": [
                ["delta": ["content": answer]],
            ],
        ]
        let chunkData = try JSONSerialization.data(withJSONObject: chunkJSON)
        guard let chunkText = String(data: chunkData, encoding: .utf8) else {
            return XCTFail("chunk JSON must be UTF-8")
        }
        let bodyText = "data: \(chunkText)\n\ndata: [DONE]\n"
        guard let body = bodyText.data(using: .utf8) else {
            return XCTFail("SSE body must encode as UTF-8")
        }

        let payloads = LLMStreamTransport.sseJSONPayloads(fromBody: body)
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(
            LLMStreamDeltaParser.chatCompletionsDelta(from: payloads[0]),
            answer
        )
    }

    func testAnswerStreamThrottleGatesByIntervalAndGrowth() {
        var throttle = AIAnswerStreamThrottle(minInterval: 1, minCharacterStep: 10)
        XCTAssertTrue(throttle.shouldPublish(accumulatedCount: 1, now: 100))
        XCTAssertFalse(throttle.shouldPublish(accumulatedCount: 5, now: 100.2))
        XCTAssertTrue(throttle.shouldPublish(accumulatedCount: 15, now: 100.2))
        XCTAssertTrue(throttle.shouldPublish(accumulatedCount: 16, now: 101.5))
        XCTAssertTrue(throttle.shouldPublish(accumulatedCount: 0, now: 101.6, force: true))
    }
}
