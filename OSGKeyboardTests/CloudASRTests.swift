// CloudASRTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class CloudASRTests: XCTestCase {

    func testCloudASRStrategyRouting() {
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "zhipu"), .zhipuHotwords)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "qwen"), .localFallback)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "bailian"), .bailianStreaming)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "openai"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "whisper"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "mimo"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "groq"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "siliconflow"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "openrouter"), .openRouterJson)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "volcengine"), .volcengineStreaming)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "moonshot"), .localFallback)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "ark"), .localFallback)
    }

    func testCloudASRModelDefaults() {
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "bailian"), "fun-asr-realtime")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "zhipu"), "glm-asr-2512")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "mimo"), "mimo-v2.5-asr")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "openai"), "gpt-4o-mini-transcribe")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "whisper"), "whisper-1")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "groq"), "whisper-large-v3-turbo")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "siliconflow"), "FunAudioLLM/SenseVoiceSmall")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "openrouter"), "openai/whisper-large-v3-turbo")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "volcengine"), "volc.seedasr.sauc.duration")
    }

    func testAsrSelectablePresetsAllowlist() {
        let ids = Set(LLMProvider.asrSelectablePresets.map(\.id))
        XCTAssertTrue(ids.contains("groq"))
        XCTAssertTrue(ids.contains("siliconflow"))
        XCTAssertTrue(ids.contains("openrouter"))
        XCTAssertTrue(ids.contains("bailian"))
        XCTAssertTrue(ids.contains("whisper"))
        XCTAssertTrue(ids.contains("volcengine"))
        XCTAssertFalse(ids.contains("qwen"))
        XCTAssertFalse(ids.contains("moonshot"))
        XCTAssertFalse(ids.contains("ark"))
        XCTAssertFalse(ids.contains("anthropic"))
        XCTAssertFalse(ids.contains("gemini"))
    }

    func testPolishOnlyProvidersExcludedFromASRPicker() {
        let polishIds = Set(LLMProvider.userSelectablePresets.map(\.id))
        let asrIds = Set(LLMProvider.asrSelectablePresets.map(\.id))
        XCTAssertTrue(polishIds.contains("ark"))
        XCTAssertFalse(asrIds.contains("ark"))
        XCTAssertTrue(polishIds.contains("gemini"))
        XCTAssertFalse(asrIds.contains("gemini"))
    }

    func testPersonalDictionaryCloudASRBadgeProviders() {
        XCTAssertTrue(LLMProvider.provider(id: "zhipu").supportsPersonalDictionaryCloudASR)
        XCTAssertFalse(LLMProvider.provider(id: "qwen").supportsPersonalDictionaryCloudASR)
        XCTAssertFalse(LLMProvider.provider(id: "bailian").supportsPersonalDictionaryCloudASR)
        XCTAssertFalse(LLMProvider.provider(id: "openai").supportsPersonalDictionaryCloudASR)
        XCTAssertFalse(LLMProvider.provider(id: "moonshot").supportsPersonalDictionaryCloudASR)
    }

    func testShowsASREndpointField() {
        XCTAssertTrue(CloudASRModelCatalog.showsASREndpointField(for: "bailian"))
        XCTAssertTrue(CloudASRModelCatalog.showsASREndpointField(for: "openai"))
        XCTAssertFalse(CloudASRModelCatalog.showsASREndpointField(for: "qwen"))
        XCTAssertFalse(CloudASRModelCatalog.showsASREndpointField(for: "volcengine"))
    }

    func testBailianMergeSegmentsDedupesOverlap() {
        let merged = BailianRealtimeASRClient.mergeSegments(["你好吗", "好吗我们"])
        XCTAssertEqual(merged, "你好吗我们")
    }

    func testBailianRunTaskMessageIncludesModel() {
        let json = BailianRealtimeASRClient.runTaskMessage(
            taskID: "task-1",
            model: "fun-asr-realtime",
            vocabularyID: nil
        )
        XCTAssertTrue(json.contains("fun-asr-realtime"))
        XCTAssertTrue(json.contains("run-task"))
        XCTAssertTrue(json.contains("\"format\":\"pcm\"") || json.contains("\"format\": \"pcm\""))
        XCTAssertTrue(json.contains("16000") || json.contains("16_000"))
    }

    func testLegacyQwenASRConfigMigratesToBailian() {
        let suite = "group.com.osgkeyboard.tests.qwen-asr.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("qwen", forKey: AppGroupConfiguration.Keys.asrProviderId)
        defaults.set("https://dashscope.aliyuncs.com/compatible-mode/v1", forKey: AppGroupConfiguration.Keys.asrBaseURL)
        defaults.set("fun-asr-flash-2026-06-15", forKey: AppGroupConfiguration.Keys.asrModel)

        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(config.asrProviderId, "bailian")
        XCTAssertEqual(config.asrBaseURL, CloudASRModelCatalog.bailianDefaultEndpoint)
        XCTAssertEqual(config.asrModel, CloudASRModelCatalog.alibabaFunASRRealtime)
    }

    func testVolcengineASRFieldsJSONParsing() {
        let json = #"{"app_id":"app-1","access_token":"tok-2","resource_id":"res-3"}"#
        let fields = VolcengineASRFields.parse(apiKey: json, resourceFallback: "")
        XCTAssertEqual(fields.appID, "app-1")
        XCTAssertEqual(fields.accessToken, "tok-2")
        XCTAssertEqual(fields.resourceID, "res-3")
    }

    func testVolcengineASRFieldsColonParsing() {
        let fields = VolcengineASRFields.parse(
            apiKey: "app-1:tok-2:res-3",
            resourceFallback: CloudASRModelCatalog.defaultModel(for: "volcengine")
        )
        XCTAssertEqual(fields.appID, "app-1")
        XCTAssertEqual(fields.accessToken, "tok-2")
        XCTAssertEqual(fields.resourceID, "res-3")
        XCTAssertTrue(fields.encodedAPIKey.contains("app-1"))
    }

    func testPersonalDictionaryASRHotwordsDedupesTerms() {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Kubernetes", category: .technical, source: .manual),
            PersonalDictionary.Entry(term: "kubernetes", category: .technical, source: .manual),
            PersonalDictionary.Entry(term: "OSGKeyboard", category: .productName, source: .manual),
        ])
        let hotwords = dict.asrHotwords()
        XCTAssertEqual(hotwords.count, 2)
        XCTAssertTrue(hotwords.contains("Kubernetes"))
        XCTAssertTrue(hotwords.contains("OSGKeyboard"))
    }

    func testPersonalDictionaryASRPromptIncludesAliases() {
        var dict = PersonalDictionary.empty
        _ = dict.upsertManual(term: "Kubernetes")
        dict.updateAliases(
            for: dict.entries[0].id,
            aliases: ["k8s", "库伯内特斯"]
        )
        let prompt = dict.asrPromptBias()
        XCTAssertTrue(prompt.contains("Kubernetes"))
        XCTAssertTrue(prompt.contains("k8s"))
    }

    func testPersonalDictionaryAlibabaHotwordEntries() {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Cursor", category: .productName, source: .manual),
        ])
        let entries = dict.alibabaHotwordEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].text, "Cursor")
        XCTAssertEqual(entries[0].weight, 4)
    }

    func testPCMSampleWavEncoderProducesHeader() {
        let wav = PCMSampleWavEncoder.encode(samples: [0.0, 0.5, -0.5], sampleRate: 16_000)
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.dropFirst(8).prefix(4), encoding: .ascii), "WAVE")
    }

    func testVocabularyFingerprintChangesWhenDictionaryChanges() {
        var dict = PersonalDictionary.empty
        let emptyFP = dict.vocabularySyncFingerprint()
        _ = dict.upsertManual(term: "OSGKeyboard")
        XCTAssertNotEqual(emptyFP, dict.vocabularySyncFingerprint())
    }
}
