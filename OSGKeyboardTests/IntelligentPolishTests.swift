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

    // MARK: - PolishingService prompt construction

    func testPolishServiceUltraShortTextSkipsLLM() async throws {
        store.setEngineMode("cloud")
        let service = PolishingService(
            store: store,
            client: ThrowingLLMClient()
        )
        let result = try await service.polish("好", context: PolishContext())
        XCTAssertEqual(result, "好")
    }

    func testPolishServiceShortStructuredTextStillInvokesLLM() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "第一点测试第二点上线",
            context: PolishContext()
        )
        XCTAssertFalse(captured.lastPrompt.isEmpty)
    }

    func testHeavyFunStylesUseSingleCreativeRequestWithoutLegacyRoutes() async throws {
        let cases = [
            ("builtin.dating", "多喝热水", "心动公式"),
            ("builtin.flex", "这个方案还行", "装腔公式"),
            ("builtin.corp", "这期可能推迟", "黑话公式"),
            ("builtin.diba", "这个结论我不同意", "拆招公式"),
            ("builtin.xhs", "这家店味道一般", "集美公式"),
        ]

        for (id, input, marker) in cases {
            store.setActivePolishStyleId(id)
            store.setPolishIntensity(.heavy)
            let captured = CapturingLLMClient()
            let service = PolishingService(store: store, client: captured)

            _ = try await service.polish(
                input,
                context: PolishContext()
            )

            XCTAssertEqual(captured.optionsHistory.count, 1, id)
            XCTAssertEqual(captured.optionsHistory.first?.temperature, 0.65, id)
            XCTAssertTrue(captured.lastPrompt.contains("趣味风格共享格式化"), id)
            XCTAssertFalse(captured.lastPrompt.contains("全局输出契约"), id)
            XCTAssertFalse(captured.lastPrompt.contains("问句守卫"), id)
            XCTAssertFalse(captured.lastPrompt.contains("参考长度范围"), id)
            XCTAssertTrue(captured.lastPrompt.contains(marker), id)
            XCTAssertFalse(captured.lastPrompt.contains("专属降级"), id)
            XCTAssertFalse(captured.lastPrompt.contains("本次方向"), id)
        }
    }

    func testLightFunStyleUsesFullSafetyPromptAndConservativeSampling() async throws {
        store.setActivePolishStyleId("builtin.dating")
        store.setPolishIntensity(.light)
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)

        _ = try await service.polish(
            "你吃饭了吗？",
            context: PolishContext(appContext: .chat)
        )

        XCTAssertEqual(captured.optionsHistory.count, 1)
        XCTAssertEqual(captured.optionsHistory.first?.temperature, 0.1)
        XCTAssertTrue(captured.lastPrompt.contains("全局输出契约"))
        XCTAssertTrue(captured.lastPrompt.contains("输入身份与抑制契约"))
        XCTAssertTrue(captured.lastPrompt.contains("# 输入环境"))
        XCTAssertFalse(captured.lastPrompt.contains("趣味风格共享格式化"))
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
            context: PolishContext(appContext: .code)
        )
        XCTAssertFalse(captured.lastPrompt.isEmpty)
    }

    func testPolishServiceMissingAPIKeyThrows() async {
        store.setEngineMode("cloud")
        // Default polish provider is deepseek; a filled PreconfiguredKeys.local
        // would satisfy hasPolishAPIKey. Use a unique provider account so a
        // developer's simulator Keychain cannot make this test hit the network.
        let missingProvider = "test-missing-\(UUID().uuidString)"
        let service = PolishingService(store: store)
        do {
            _ = try await service.polish(
                "hello world",
                providerIdOverride: missingProvider,
                context: PolishContext()
            )
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
        let result = try await service.polish("明天见", context: PolishContext())
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
            context: PolishContext(appContext: .code)
        )
        XCTAssertTrue(captured.lastPrompt.contains("Kubernetes"),
                      "Prompt must include dictionary term. Got: \(captured.lastPrompt)")
        XCTAssertTrue(captured.lastPrompt.contains("代码或技术环境"),
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

    func testSystemPromptDoesNotContainTranscriptAndUserPayloadIsEscaped() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        let input = "这是一段独一无二的测试转写文本ZZQQ"
        _ = try await service.polish(input, context: PolishContext())
        XCTAssertFalse(captured.lastPrompt.contains("ZZQQ"))
        XCTAssertTrue(captured.lastText.contains("<dictation_request protocol=\"polish-v1\">"))
        XCTAssertTrue(captured.lastText.contains(input))
    }

    func testChineseInputUsesChineseGuidanceOnOpenAI() async throws {
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "今天讨论 roadmap 和发布时间",
            providerIdOverride: "openai",
            context: PolishContext()
        )
        XCTAssertTrue(captured.lastPrompt.contains("全局输出契约"))
    }

    func testPromptIncludesPrecedingFollowingAndFieldHints() async throws {
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "下午三点应该可以",
            context: PolishContext(
                appContext: .chat,
                precedingText: "明天的会我看了下日程",
                followingText: "确认后告诉我",
                fieldHints: FieldHints(
                    returnKeyType: "send",
                    isEmptyField: false,
                    isContextAvailable: true
                )
            )
        )
        XCTAssertTrue(captured.lastPrompt.contains("明天的会我看了下日程"))
        XCTAssertTrue(captured.lastPrompt.contains("确认后告诉我"))
        XCTAssertTrue(captured.lastPrompt.contains("衔接规则"))
    }

    func testCorePromptIsStableAcrossCalls() {
        XCTAssertEqual(
            PolishPromptComposer.chineseCorePrompt,
            PolishPromptComposer.chineseCorePrompt
        )
        XCTAssertFalse(PolishPromptComposer.chineseCorePrompt.contains("{{"))
        XCTAssertTrue(PolishPromptComposer.chineseCorePrompt.contains("T1 自我修正合并"))
        XCTAssertTrue(PolishPromptComposer.chineseCorePrompt.contains("T3 同音/近音纠错"))
        XCTAssertTrue(PolishPromptComposer.chineseCorePrompt.contains("先完成 T1–T3"))
        XCTAssertTrue(PolishPromptComposer.chineseCorePrompt.contains("在见一面"))
        XCTAssertTrue(PolishPromptComposer.englishCorePrompt.contains("Homophone / near-homophone repair"))
        XCTAssertTrue(PolishPromptComposer.englishCorePrompt.contains("let's meat again"))
    }

    func testPolishServicePromptIncludesStructureRules() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "今天有三个任务第一点修复登录第二点优化键盘",
            context: PolishContext()
        )
        XCTAssertTrue(
            captured.lastPrompt.contains("第一点") || captured.lastPrompt.contains("numbered"),
            "Prompt must include structure rules. Got: \(captured.lastPrompt.prefix(300))"
        )
    }

    func testPolishServiceScalesTimeoutWithTextLength() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured, timeout: 15)
        let longText = String(repeating: "这是一段比较长的语音识别测试文本，", count: 20)
        _ = try await service.polish(longText, context: PolishContext())
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
        _ = try await service.polish(veryLong, context: PolishContext())
        let passedTimeout = try XCTUnwrap(captured.lastTimeout)
        XCTAssertLessThanOrEqual(passedTimeout, 120)
    }

    func testPolishServiceUsesChineseForChineseProviders() async throws {
        store.setEngineMode("local")
        let captured = CapturingLLMClient()
        let service = PolishingService(store: store, client: captured)
        _ = try await service.polish(
            "今天我们部署 k8s 集群",
            context: PolishContext()
        )
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
            context: PolishContext()
        )
        XCTAssertFalse(result.contains("👍"))
        XCTAssertTrue(result.contains("完成"))
    }

    func testPolishServiceKeepsAddedEmojiWhenStyleAllows() async throws {
        store.setEngineMode("local")
        var catalog = PolishStyleCatalog()
        let pack = PolishStylePack(
            id: "user.emoji",
            name: "Emoji",
            prompt: "保持口语，可按情绪加 emoji。",
            allowsAddedEmoji: true
        )
        try catalog.upsert(pack)
        store.setPolishStyleCatalog(catalog)
        store.setActivePolishStyleId(pack.id)

        let emojiClient = FixedResponseLLMClient(response: "今天太开心了，终于搞定了😆")
        let service = PolishingService(store: store, client: emojiClient)
        let result = try await service.polish(
            "今天太开心了终于搞定了",
            context: PolishContext()
        )
        XCTAssertTrue(result.contains("😆"), "Allowed-emoji styles must keep model-added emoji. Got: \(result)")
        XCTAssertTrue(result.contains("开心"))
    }

    func testPolishServiceKeepsAddedEmojiWhenPromptOptsInWithoutToggle() async throws {
        store.setEngineMode("local")
        var catalog = PolishStyleCatalog()
        let pack = PolishStylePack(
            id: "user.paste-emoji",
            name: "PasteEmoji",
            prompt: "本风格允许新增 emoji。按情绪点缀合适表情。",
            allowsAddedEmoji: false
        )
        try catalog.upsert(pack)
        store.setPolishStyleCatalog(catalog)
        store.setActivePolishStyleId(pack.id)

        let emojiClient = FixedResponseLLMClient(response: "辛苦你了，真的谢谢🙏")
        let service = PolishingService(store: store, client: emojiClient)
        let result = try await service.polish(
            "辛苦你了真的谢谢",
            context: PolishContext()
        )
        XCTAssertTrue(
            result.contains("🙏"),
            "Prompt opt-in must keep emoji even when toggle is off. Got: \(result)"
        )
    }

    func testPolishServiceFallsBackWhenOutputEmpty() async throws {
        store.setEngineMode("local")
        let emptyClient = FixedResponseLLMClient(response: "   ")
        let service = PolishingService(store: store, client: emptyClient)
        let result = try await service.polish(
            "今天的部署已经全部完成",
            context: PolishContext()
        )
        XCTAssertEqual(result, "今天的部署已经全部完成")
    }

    func testValidatorFallsBackAfterSingleHardFailure() async throws {
        let client = ValidationFailureLLMClient()
        let service = PolishingService(store: store, client: client)
        let outcome = try await service.polishWithOutcome(
            "please keep user_id in this technical message",
            context: PolishContext(appContext: .code)
        )
        XCTAssertEqual(outcome.text, "please keep user_id in this technical message")
        XCTAssertTrue(outcome.qualityDegraded)
        XCTAssertEqual(client.temperatures.compactMap { $0 }, [0.1])
    }

    func testValidatorFallsBackToMinimalPolishAfterHardFailure() async throws {
        let service = PolishingService(
            store: store,
            client: FixedResponseLLMClient(response: "Please keep it.")
        )
        let outcome = try await service.polishWithOutcome(
            "um please keep user_id",
            context: PolishContext(appContext: .code)
        )
        XCTAssertEqual(outcome.text, "please keep user_id")
        XCTAssertTrue(outcome.qualityDegraded)
    }

    // MARK: - TranscriptPostProcessor

    func testShouldSkipLLMForUltraShortWithoutStructure() {
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "好"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "OK"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "明天见"))
    }

    func testShouldSkipLLMTier2ForAckClosings() {
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "好的我知道了"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "那就先这样吧"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "晚点再说"))
        XCTAssertTrue(TranscriptPostProcessor.shouldSkipLLM(for: "收到谢谢"))
    }

    func testShouldNotSkipLLMTier2ForQuestionsOrContent() {
        XCTAssertFalse(TranscriptPostProcessor.shouldSkipLLM(for: "今晚有空吗"))
        XCTAssertFalse(TranscriptPostProcessor.shouldSkipLLM(for: "这个还行吧"))
        XCTAssertFalse(TranscriptPostProcessor.shouldSkipLLM(for: "周六一起吃饭"))
        XCTAssertFalse(TranscriptPostProcessor.shouldSkipLLM(for: "防晒不由夏天"))
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

    func testQualityGateKeepsAddedEmojiWhenAllowed() {
        let decision = TranscriptPostProcessor.qualityGate(
            original: "今天太开心了",
            candidate: "今天太开心了😆",
            allowsAddedEmoji: true
        )
        guard case .accept(let text) = decision else {
            return XCTFail("Expected accept")
        }
        XCTAssertTrue(text.contains("😆"))
    }

    func testQualityGateStripsAddedEmojiByDefault() {
        let decision = TranscriptPostProcessor.qualityGate(
            original: "今天太开心了",
            candidate: "今天太开心了😆",
            allowsAddedEmoji: false
        )
        guard case .accept(let text) = decision else {
            return XCTFail("Expected accept")
        }
        XCTAssertFalse(text.contains("😆"))
    }

    func testQualityGateStripsResidualPauseMarkers() {
        let result = TranscriptPostProcessor.process(
            original: "第一段 ⟨0.8s⟩ 第二段",
            llmOutput: "第一段 ⟨0.8s⟩ 第二段"
        )
        XCTAssertFalse(result.contains("⟨"))
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

    func testCleanRawASRFallbackRemovesChineseInteriorSpaces() {
        let input = "  你 是不是 已经 解决了 这个 问题 ？  "
        let output = TranscriptPostProcessor.cleanRawASRFallback(input)
        XCTAssertEqual(output, "你是不是已经解决了这个问题？")
    }

    func testCleanRawASRFallbackPreservesEnglishAndMixedSpaces() {
        let input = "iOS 版本 uses Swift UI"
        let output = TranscriptPostProcessor.cleanRawASRFallback(input)
        XCTAssertEqual(output, "iOS 版本 uses Swift UI")
    }

    @MainActor
    func testFlowFallbackDeliveryCleansTextAndCarriesWeakNetworkWarning() {
        let delivery = TranscriptionPolishFallback.makeDelivery(
            rawText: "  你 是不是 已经 解决了 这个 问题 ？  ",
            error: LLMError.transport("offline"),
            engineMode: "cloud",
            chunkWarning: nil
        )

        XCTAssertEqual(delivery.text, "你是不是已经解决了这个问题？")
        XCTAssertFalse(delivery.text.contains("未润色"))
        XCTAssertEqual(delivery.polishWarning, SharedL10n.string("flow.warning.polishDegraded"))
    }

    func testTranscriptionPolishFallbackLocalMissingKeyWarning() {
        let delivery = TranscriptionPolishFallback.makeDelivery(
            rawText: "测试文本",
            error: PolishingService.PolishError.missingAPIKey,
            engineMode: "local",
            chunkWarning: nil
        )
        XCTAssertEqual(delivery.text, "测试文本")
        XCTAssertEqual(
            delivery.polishWarning,
            SharedL10n.string("flow.warning.localPolishUnavailable")
        )
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

    func testChatTranslationGuidelineDoesNotEncourageEmoji() {
        let guideline = AppContext.chat.translationGuideline
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
    private(set) var lastText: String = ""
    private(set) var lastTimeout: TimeInterval?
    private(set) var lastOptions: LLMGenerationOptions?
    private(set) var optionsHistory: [LLMGenerationOptions] = []
    let requestTimeout: TimeInterval = 15

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        lastText = text
        lastPrompt = systemPrompt
        lastTimeout = timeout
        return text
    }

    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        lastOptions = options
        optionsHistory.append(options)
        return try await polish(
            text,
            systemPrompt: systemPrompt,
            timeout: timeout
        )
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

private final class ValidationFailureLLMClient: LLMClient, @unchecked Sendable {
    let requestTimeout: TimeInterval = 15
    private(set) var temperatures: [Double?] = []

    func polish(_ text: String, systemPrompt: String, timeout: TimeInterval?) async throws -> String {
        "Please keep it."
    }

    func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        temperatures.append(options.temperature)
        return "Please keep it."
    }
}
