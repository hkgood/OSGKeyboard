// IntelligentPolishTests.swift
// OSGKeyboard · Tests
//
// v0.3.0: locks the behavior of the rewritten PolishingService and
// its supporting service (AppContextDetector).
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
        suiteName = "group.com.osgkeyboard.shared.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Polish intensity migration

    func testPolishIntensityMigratesLegacyOffToMedium() {
        defaults.set(PolishIntensity.legacyOffRawValue, forKey: "config.polishIntensity")
        XCTAssertEqual(store.polishIntensity, .medium)
        XCTAssertEqual(defaults.string(forKey: "config.polishIntensity"), PolishIntensity.medium.rawValue)
    }

    func testPolishIntensityResolveLegacyOff() {
        XCTAssertEqual(PolishIntensity.resolve(storedRawValue: "off"), .medium)
    }

    // MARK: - PolishingService prompt construction

    func testPolishServiceUltraShortTextSkipsLLM() async throws {
        store.setEngineMode("cloud")
        let service = PolishingService(
            store: store,
            client: ThrowingLLMClient()
        )
        let result = try await service.polish("好", context: PolishContext(intensity: .heavy))
        XCTAssertEqual(result, "好")
    }

    func testPolishServiceShortStructuredTextStillInvokesLLM() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "第一点测试第二点上线",
            context: PolishContext(intensity: .medium)
        )
        XCTAssertFalse(captured.lastPrompt.isEmpty)
    }

    func testPersonalDictionaryUpsertManual() {
        var dict = PersonalDictionary.empty
        let entry = dict.upsertManual(term: "Kubernetes")
        XCTAssertEqual(entry?.term, "Kubernetes")
        XCTAssertEqual(entry?.source, .manual)
        XCTAssertEqual(dict.entries.count, 1)

        let updated = dict.upsertManual(term: "kubernetes", existingID: entry?.id)
        XCTAssertEqual(updated?.term, "kubernetes")
        XCTAssertEqual(dict.entries.count, 1)
    }

    func testDictionaryAliasGeneratorParsesJSONArray() {
        let aliases = DictionaryAliasGenerator.parseAliases(
            from: #"["k8s","库伯内特斯"]"#,
            excludingTerm: "Kubernetes"
        )
        XCTAssertEqual(aliases, ["k8s", "库伯内特斯"])
    }

    func testDictionaryAliasGeneratorExcludesCanonicalTerm() {
        let aliases = DictionaryAliasGenerator.parseAliases(
            from: #"["Kubernetes","k8s"]"#,
            excludingTerm: "Kubernetes"
        )
        XCTAssertEqual(aliases, ["k8s"])
    }

    func testEntryInferCategoryForChinese() {
        XCTAssertEqual(PersonalDictionary.Entry.inferCategory(for: "张三"), .properNoun)
        XCTAssertEqual(PersonalDictionary.Entry.inferCategory(for: "LLM"), .acronym)
    }

    func testPersonalDictionaryMigratesLegacyHistorySource() {
        let legacy = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Kubernetes", category: .productName, source: .history),
        ])
        let data = try! JSONEncoder().encode(legacy)
        defaults.set(data, forKey: "config.personalDictionary.v1")

        let loaded = store.personalDictionary
        XCTAssertEqual(loaded.entries.first?.source, .manual)
        XCTAssertEqual(loaded.entries.first?.term, "Kubernetes")
    }

    func testPolishServiceLocalEngineInvokesLLM() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "今天我们部署 k8s 集群",
            context: PolishContext(appContext: .code, intensity: .medium)
        )
        XCTAssertFalse(captured.lastPrompt.isEmpty)
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
        XCTAssertTrue(
            captured.lastPrompt.contains("全局输出契约") || captured.lastPrompt.contains("Global output contract"),
            "Prompt must include global output contract. Got: \(captured.lastPrompt.prefix(200))"
        )
        XCTAssertTrue(
            captured.lastPrompt.localizedCaseInsensitiveContains("emoji"),
            "Prompt must include strict emoji control guidance. Got: \(captured.lastPrompt)"
        )
        XCTAssertFalse(
            captured.lastPrompt.localizedCaseInsensitiveContains("emoji-friendly"),
            "Chat context must not encourage emojis. Got: \(captured.lastPrompt)"
        )
    }

    func testPolishServicePromptIncludesStructureRulesAtLightIntensity() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "今天有三个任务第一点修复登录第二点优化键盘",
            context: PolishContext(intensity: .light)
        )
        XCTAssertTrue(
            captured.lastPrompt.contains("第一点") || captured.lastPrompt.contains("numbered"),
            "Light intensity must still include structure rules. Got: \(captured.lastPrompt.prefix(300))"
        )
    }

    func testPolishServiceScalesTimeoutWithTextLength() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured, timeout: 15)
        let longText = String(repeating: "这是一段比较长的语音识别测试文本，", count: 20)
        _ = try await service.polish(longText, context: PolishContext(intensity: .medium))
        let passedTimeout = try XCTUnwrap(captured.lastTimeout)
        XCTAssertGreaterThan(
            passedTimeout, 15,
            "Long transcripts must scale the per-request HTTP timeout above the baseline"
        )
    }

    func testPolishServiceCapsTimeoutAt120() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured, timeout: 15)
        let veryLong = String(repeating: "测试", count: 2000)
        _ = try await service.polish(veryLong, context: PolishContext(intensity: .medium))
        let passedTimeout = try XCTUnwrap(captured.lastTimeout)
        XCTAssertLessThanOrEqual(passedTimeout, 120)
    }

    func testPolishServiceUsesChineseForChineseProviders() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish("hello", context: PolishContext(intensity: .medium))
        XCTAssertTrue(
            captured.lastPrompt.contains("全局输出契约"),
            "Local engine should get the Chinese prompt via DeepSeek. Got prefix: \(captured.lastPrompt.prefix(80))"
        )
    }

    func testPolishServiceStripsAddedEmojiFromLLMOutput() async throws {
        store.setEngineMode("local")
        let emojiClient = FixedResponseLLMClient(response: "今天的工作已经全部完成了👍")
        let service = PolishingService(store: store, client: emojiClient)
        let result = try await service.polish(
            "今天的工作已经全部完成了",
            context: PolishContext(intensity: .medium)
        )
        XCTAssertFalse(result.contains("👍"))
        XCTAssertTrue(result.contains("完成"))
    }

    func testPolishServiceFallsBackWhenOutputEmpty() async throws {
        store.setEngineMode("local")
        let emptyClient = FixedResponseLLMClient(response: "   ")
        let service = PolishingService(store: store, client: emptyClient)
        let result = try await service.polish(
            "今天的部署已经全部完成",
            context: PolishContext(intensity: .medium)
        )
        XCTAssertEqual(result, "今天的部署已经全部完成")
    }

    // MARK: - TranscriptPostProcessor

    func testShouldSkipLLMForUltraShortWithoutStructure() {
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "好"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "OK"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "明天见"))
    }

    func testShouldNotSkipLLMWhenStructurePresent() {
        XCTAssertFalse(TranscriptPostProcessor.shouldSkipLLM(for: "第一点做完第二点再做"))
    }

    func testStripAddedEmojisRemovesNewEmoji() {
        let result = TranscriptPostProcessor.stripAddedEmojis(
            original: "好的",
            output: "好的👍"
        )
        XCTAssertEqual(result, "好的")
    }

    func testNormalizeNumberedLists() {
        let input = "第一点 修复\n第二点 上线"
        let output = TranscriptPostProcessor.normalizeNumberedLists(input)
        XCTAssertTrue(output.contains("1. 修复"))
        XCTAssertTrue(output.contains("2. 上线"))
    }

    func testQualityGateNeverRevertsToRawOnNumberChange() {
        // Listifying / fixing ASR number-mishearings legitimately
        // changes the number set — this must NOT revert to the raw text.
        let decision = TranscriptPostProcessor.qualityGate(
            original: "第一点测试第2:00上线",
            candidate: "1. 测试\n2. 上线"
        )
        if case .accept(let text) = decision {
            XCTAssertTrue(text.contains("1. 测试"))
            XCTAssertTrue(text.contains("2. 上线"))
        } else {
            XCTFail("Expected accept — number changes must not trigger raw fallback")
        }
    }

    func testQualityGateStillFallsBackOnEmptyOutput() {
        let decision = TranscriptPostProcessor.qualityGate(
            original: "部署完成",
            candidate: "   "
        )
        if case .fallback(let text) = decision {
            XCTAssertEqual(text, "部署完成")
        } else {
            XCTFail("Expected fallback on empty output")
        }
    }

    func testRepairMidSentenceLineBreakJoinsBrokenSentence() {
        let input = "你是不是真的解决了这个格式化和标点符号包括\n这些问题"
        let output = TranscriptPostProcessor.repairMidSentenceLineBreaks(input)
        XCTAssertEqual(output, "你是不是真的解决了这个格式化和标点符号包括这些问题")
    }

    func testRepairMidSentenceLineBreakKeepsSentenceBoundary() {
        let input = "今天完成了部署。\n明天开始测试。"
        let output = TranscriptPostProcessor.repairMidSentenceLineBreaks(input)
        XCTAssertEqual(output, input)
    }

    func testRepairMidSentenceLineBreakKeepsListItems() {
        let input = "1. 修复登录\n2. 优化键盘"
        let output = TranscriptPostProcessor.repairMidSentenceLineBreaks(input)
        XCTAssertEqual(output, input)
    }

    func testRepairMidSentenceLineBreakJoinsEnglishWithSpace() {
        let input = "this is a broken\nsentence"
        let output = TranscriptPostProcessor.repairMidSentenceLineBreaks(input)
        XCTAssertEqual(output, "this is a broken sentence")
    }

    func testHasStructureSignalDetectsChineseEnumeration() {
        XCTAssertTrue(TranscriptPostProcessor.hasStructureSignal(in: "首先测试其次上线"))
        XCTAssertTrue(TranscriptPostProcessor.hasStructureSignal(in: "第一点修复"))
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
        let env = detector.detect(
            precedingText: nil,
            storedCache: nil,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertNotEqual(env, .unknown)
    }

    func testAppContextDetectorCacheWinsOverFallback() {
        let detector = AppContextDetector()
        let cache = (context: AppContext.code, observedAt: Date().addingTimeInterval(-300))
        let result = detector.detect(precedingText: "", storedCache: cache)
        XCTAssertEqual(result, .code)
    }

    func testChatAppContextGuidelineDoesNotEncourageEmoji() {
        let guideline = AppContext.chat.polishGuideline
        XCTAssertFalse(guideline.localizedCaseInsensitiveContains("emoji-friendly"))
        XCTAssertTrue(guideline.localizedCaseInsensitiveContains("Do not add emojis"))
    }

    // MARK: - PersonalDictionary.promptFragment

    func testDictionaryPromptFragmentIncludesBuiltInOSGKeyboard() {
        let prompt = PersonalDictionary.empty.promptFragment()
        XCTAssertTrue(prompt.contains("OSGKeyboard"))
    }

    func testDictionaryPromptFragmentGroupsByCategory() {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Kubernetes", category: .productName, source: .manual),
            PersonalDictionary.Entry(term: "iOS", category: .acronym, source: .manual),
            PersonalDictionary.Entry(term: "Rocky", category: .properNoun, source: .manual),
        ])
        let prompt = dict.promptFragment()
        XCTAssertTrue(prompt.contains("OSGKeyboard"))
        XCTAssertTrue(prompt.contains("Kubernetes"))
        XCTAssertTrue(prompt.contains("iOS"))
        XCTAssertTrue(prompt.contains("Rocky"))
    }
}

// MARK: - Test doubles

private final class CapturingLLMClient: LLMClient, @unchecked Sendable {
    private(set) var lastPrompt: String = ""
    private(set) var lastTimeout: TimeInterval?
    let requestTimeout: TimeInterval = 15

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        lastPrompt = systemPrompt
        lastTimeout = timeout
        return text
    }
}

private final class EchoLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String { text }
}

private final class ThrowingLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        throw LLMError.cancelled
    }
}

private final class FixedResponseLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    private let response: String

    init(response: String) {
        self.response = response
    }

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        response
    }
}
