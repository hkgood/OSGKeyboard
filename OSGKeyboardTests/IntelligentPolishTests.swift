// IntelligentPolishTests.swift
// OSGKeyboard · Tests
//
// v0.3.0: locks the behavior of the rewritten PolishingService and
// its two supporting services (AppContextDetector, DictionaryLearner).
// The tests are deliberately hermetic — no LLMClient, no ASR, no
// App Group — so they run in <100 ms total.

import XCTest
@testable import OSGKeyboard
@testable import OSGKeyboardShared

final class IntelligentPolishTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        // Each test gets a fresh, throwaway UserDefaults suite so
        // engine mode / API key / dictionary / context state does
        // not leak between tests. The AppGroupStore falls back to
        // `.standard` when no App Group entitlement is present, so
        // we point it at a private suite to keep this test hermetic.
        suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - PolishingService prompt construction

    func testPolishServiceOffIntensitySkipsLLM() async throws {
        // When intensity is `.off`, the service must return the
        // raw input unchanged *and* not touch the LLM. We assert
        // both by passing a deliberately broken LLM client and
        // expecting the call to return cleanly.
        store.setEngineMode("cloud")
        let service = PolishingService(
            store: store,
            client: ThrowingLLMClient()  // would throw if invoked
        )
        let result = try await service.polish("hello world", context: PolishContext(intensity: .off))
        XCTAssertEqual(result, "hello world")
    }

    func testPolishServiceLocalEngineWithoutCloudPolishReturnsRaw() async throws {
        store.setEngineMode("local")
        // localModeCloudPolishEnabled defaults to false.
        let service = PolishingService(
            store: store,
            client: ThrowingLLMClient()
        )
        let result = try await service.polish("hello world", context: PolishContext(intensity: .medium))
        XCTAssertEqual(result, "hello world")
    }

    func testPolishServiceMissingAPIKeyThrows() async {
        store.setEngineMode("cloud")
        let service = PolishingService(
            store: store,
            client: EchoLLMClient()
        )
        do {
            _ = try await service.polish("hello world", context: PolishContext(intensity: .medium))
            XCTFail("Expected missingAPIKey")
        } catch let error as PolishingService.PolishError {
            XCTAssertEqual(error, .missingAPIKey)
        } catch {
            XCTFail("Expected PolishError, got \(error)")
        }
    }

    func testPolishServiceShortTextSkipsLLM() async throws {
        // Per the prompt's hard rule #4, ≤ 8 CJK chars / ≤ 15
        // English words must be returned verbatim. We exercise
        // the upper bound here.
        store.setEngineMode("cloud")
        let service = PolishingService(
            store: store,
            client: ThrowingLLMClient()
        )
        let result = try await service.polish("明天见", context: PolishContext(intensity: .heavy))
        XCTAssertEqual(result, "明天见")
    }

    func testPolishServiceBuildsPromptWithDictionaryAndContext() async throws {
        store.setEngineMode("cloud")
        store.personalDictionary = PersonalDictionary(entries: [
            PersonalDictionary.Entry(
                term: "Kubernetes", category: .productName, source: .manual
            ),
        ])
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "今天我们部署 k8s 集群",
            context: PolishContext(appContext: .code, intensity: .medium)
        )
        XCTAssertTrue(captured.lastPrompt.contains("Kubernetes"),
                      "Prompt must include dictionary term. Got: \(captured.lastPrompt)")
        XCTAssertTrue(captured.lastPrompt.contains("Code context"),
                      "Prompt must include app-context guideline. Got: \(captured.lastPrompt)")
        XCTAssertTrue(captured.lastPrompt.contains("medium") || captured.lastPrompt.contains("中度"),
                      "Prompt must mention the intensity. Got: \(captured.lastPrompt)")
    }

    func testPolishServiceUsesChineseForChineseProviders() async throws {
        defaults.set("deepseek", forKey: "config.providerId")
        store.setEngineMode("cloud")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish("hello", context: PolishContext(intensity: .medium))
        // The polisher routes Chinese providers through the Chinese
        // prompt, which is identifiable by its "三件事" header.
        XCTAssertTrue(
            captured.lastPrompt.contains("三件事"),
            "DeepSeek should get the Chinese prompt. Got prefix: \(captured.lastPrompt.prefix(80))"
        )
    }

    // MARK: - AppContextDetector

    func testAppContextDetectorRecognizesCodeByIndentation() {
        let detector = AppContextDetector()
        let text = """
        import Foundation
        struct Foo {
            func bar() -> Int {
                return 42
            }
        }
        """
        XCTAssertEqual(detector.heuristicDetect(preceding: text), .code)
    }

    func testAppContextDetectorRecognizesEmail() {
        let detector = AppContextDetector()
        let text = "Hi Rocky,\n\nFollowing up on rocky.hk@gmail.com thread — can you sign off by Friday?\n\nThanks,\nLily"
        XCTAssertEqual(detector.heuristicDetect(preceding: text), .email)
    }

    func testAppContextDetectorRecognizesChat() {
        let detector = AppContextDetector()
        let text = "ok\nlol\nsee you tmr\nbrb\nbbl\nk\nthx"
        XCTAssertEqual(detector.heuristicDetect(preceding: text), .chat)
    }

    func testAppContextDetectorRecognizesDocument() {
        let detector = AppContextDetector()
        let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 30)
        XCTAssertEqual(detector.heuristicDetect(preceding: text), .document)
    }

    func testAppContextDetectorReturnsNilOnEmpty() {
        let detector = AppContextDetector()
        XCTAssertNil(detector.heuristicDetect(preceding: ""))
    }

    func testAppContextDetectorFallbackChain() {
        let detector = AppContextDetector()
        // No preceding text and no cache → environmental fallback.
        let env = detector.detect(
            precedingText: nil,
            storedCache: nil,
            now: Date(timeIntervalSince1970: 1_700_000_000)  // a workday moment
        )
        XCTAssertNotEqual(env, .unknown)
    }

    func testAppContextDetectorCacheWinsOverFallback() {
        let detector = AppContextDetector()
        // 5-minute-old cache with `.code` must be returned even
        // when there is no preceding text.
        let cache = (context: AppContext.code, observedAt: Date().addingTimeInterval(-300))
        let result = detector.detect(precedingText: "", storedCache: cache)
        XCTAssertEqual(result, .code)
    }

    // MARK: - PersonalDictionary.promptFragment

    func testDictionaryPromptFragmentIsEmptyForEmptyDictionary() {
        let prompt = PersonalDictionary.empty.promptFragment()
        XCTAssertEqual(prompt, "")
    }

    func testDictionaryPromptFragmentGroupsByCategory() {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Kubernetes", category: .productName, source: .manual),
            PersonalDictionary.Entry(term: "iOS", category: .acronym, source: .manual),
            PersonalDictionary.Entry(term: "Rocky", category: .properNoun, source: .manual),
        ])
        let prompt = dict.promptFragment()
        XCTAssertTrue(prompt.contains("Kubernetes"))
        XCTAssertTrue(prompt.contains("iOS"))
        XCTAssertTrue(prompt.contains("Rocky"))
    }

    // MARK: - DictionaryLearner

    func testLearnerPromotesRepeatedCapitalizedToken() {
        let history: [SpeechHistoryEntry] = [
            .init(text: "Deploy Kubernetes today", engineMode: "cloud"),
            .init(text: "Restart Kubernetes pod", engineMode: "cloud"),
        ]
        let learner = DictionaryLearner(minOccurrences: 2)
        let added = learner.learn(from: history)
        XCTAssertTrue(added.contains { $0.term == "Kubernetes" },
                      "Kubernetes should be promoted. Got: \(added.map(\.term))")
    }

    func testLearnerIgnoresStopwords() {
        let history: [SpeechHistoryEntry] = [
            .init(text: "this is the test", engineMode: "cloud"),
            .init(text: "this is the second test", engineMode: "cloud"),
            .init(text: "this is the third test", engineMode: "cloud"),
        ]
        let learner = DictionaryLearner(minOccurrences: 2)
        let added = learner.learn(from: history)
        let terms = Set(added.map(\.term))
        XCTAssertFalse(terms.contains("this"))
        XCTAssertFalse(terms.contains("the"))
        XCTAssertFalse(terms.contains("is"))
    }

    func testLearnerRespectsMinimumOccurrence() {
        let history: [SpeechHistoryEntry] = [
            .init(text: "First time mentioning Whisper", engineMode: "cloud"),
        ]
        let learner = DictionaryLearner(minOccurrences: 2)
        let added = learner.learn(from: history)
        XCTAssertFalse(added.contains { $0.term == "Whisper" })
    }

    func testLearnerIdempotent() {
        let history: [SpeechHistoryEntry] = [
            .init(text: "OpenAI rocks", engineMode: "cloud"),
            .init(text: "OpenAI again", engineMode: "cloud"),
        ]
        let learner = DictionaryLearner(minOccurrences: 2)
        let first = learner.learn(from: history)
        let second = learner.learn(from: history)
        XCTAssertTrue(first.contains { $0.term == "OpenAI" })
        // Second call must not double-add; the existing entry's
        // usage count is bumped instead.
        let openaiEntries = second.filter { $0.term == "OpenAI" }
        XCTAssertEqual(openaiEntries.count, 1)
    }
}

// MARK: - Test doubles

/// Records every call so the test can inspect the prompt the
/// polisher would have sent. We do not assert on `response`; the
/// LLMClient contract is exercised by `LLMClientTests`.
private final class CapturingLLMClient: LLMClient, @unchecked Sendable {
    private(set) var lastPrompt: String = ""
    let requestTimeout: TimeInterval = 15

    func polish(_ text: String, systemPrompt: String) async throws -> String {
        lastPrompt = systemPrompt
        return text
    }
}

private final class EchoLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    func polish(_ text: String, systemPrompt: String) async throws -> String { text }
}

private final class ThrowingLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    func polish(_ text: String, systemPrompt: String) async throws -> String {
        throw LLMError.cancelled
    }
}
