// CloudASRTests.swift
// OSGKeyboardTests

@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

final class CloudASRTests: XCTestCase {

    func testCloudASRStrategyRouting() {
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "zhipu"), .zhipuHotwords)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "qwen"), .localFallback)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "bailian"), .bailianStreaming)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "openai"), .openaiRealtimeStreaming)
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
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "openai"), "gpt-realtime-whisper")
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

    func testTrueStreamingASRProviders() {
        XCTAssertTrue(CloudASRModelCatalog.supportsTrueStreamingASR(for: "bailian"))
        XCTAssertTrue(CloudASRModelCatalog.supportsTrueStreamingASR(for: "volcengine"))
        XCTAssertTrue(CloudASRModelCatalog.supportsTrueStreamingASR(for: "openai"))
        XCTAssertTrue(LLMProvider.provider(id: "bailian").supportsStreamingCloudASR)
        XCTAssertTrue(LLMProvider.provider(id: "volcengine").supportsStreamingCloudASR)
        XCTAssertTrue(LLMProvider.provider(id: "openai").supportsStreamingCloudASR)
        XCTAssertFalse(CloudASRModelCatalog.supportsTrueStreamingASR(for: "mimo"))
        XCTAssertFalse(CloudASRModelCatalog.supportsTrueStreamingASR(for: "zhipu"))
        XCTAssertFalse(CloudASRModelCatalog.supportsTrueStreamingASR(for: "groq"))
        XCTAssertFalse(CloudASRModelCatalog.supportsTrueStreamingASR(for: "whisper"))
    }

    func testUpsample16kTo24kPreservesDurationRatio() {
        let input = [Float](repeating: 0.25, count: 1_600) // 100 ms @ 16 kHz
        let output = CloudASRStreamingPCM.upsample16kTo24k(input)
        XCTAssertEqual(output.count, 2_400) // 100 ms @ 24 kHz
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

    func testLegacyQwenASRConfigCopiesDedicatedKeyToBailian() throws {
        clearQwenMigrationKeys()
        defer { clearQwenMigrationKeys() }
        let suite = "group.com.osgkeyboard.tests.qwen-asr-key.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: AppGroupConfiguration.Keys.settingsICloudSyncEnabled)
        defaults.set("qwen", forKey: AppGroupConfiguration.Keys.asrProviderId)
        try Keychain.setASRAPIKey("dedicated-credential", for: "qwen", useICloudSync: false)

        _ = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertNotNil(Keychain.asrApiKey(for: "qwen", preferICloudSync: false))
        XCTAssertNotNil(Keychain.asrApiKey(for: "bailian", preferICloudSync: false))
    }

    func testLegacyQwenASRConfigFallsBackToProviderKey() throws {
        clearQwenMigrationKeys()
        defer { clearQwenMigrationKeys() }
        let suite = "group.com.osgkeyboard.tests.qwen-provider-key.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: AppGroupConfiguration.Keys.settingsICloudSyncEnabled)
        defaults.set("qwen", forKey: AppGroupConfiguration.Keys.asrProviderId)
        try Keychain.setAPIKey("provider-credential", for: "qwen", useICloudSync: false)

        _ = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertNotNil(Keychain.apiKey(for: "qwen", preferICloudSync: false))
        XCTAssertNotNil(Keychain.asrApiKey(for: "bailian", preferICloudSync: false))
    }

    func testLegacyQwenASRConfigDoesNotOverwriteDifferentBailianKey() throws {
        clearQwenMigrationKeys()
        defer { clearQwenMigrationKeys() }
        let suite = "group.com.osgkeyboard.tests.qwen-key-conflict.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: AppGroupConfiguration.Keys.settingsICloudSyncEnabled)
        defaults.set("qwen", forKey: AppGroupConfiguration.Keys.asrProviderId)
        try Keychain.setASRAPIKey("qwen-credential", for: "qwen", useICloudSync: false)
        try Keychain.setASRAPIKey("bailian-credential", for: "bailian", useICloudSync: false)

        _ = AppGroupConfiguration.load(fromAvailable: defaults)

        XCTAssertTrue(
            Keychain.asrApiKey(for: "bailian", preferICloudSync: false)
                == "bailian-credential"
        )
        XCTAssertNotNil(Keychain.asrApiKey(for: "qwen", preferICloudSync: false))
    }

    func testVolcengineASRFieldsJSONParsing() {
        let json = #"{"app_id":"app-1","access_token":"tok-2","resource_id":"res-3"}"#
        let fields = VolcengineASRFields.parse(apiKey: json, resourceFallback: "")
        XCTAssertEqual(fields.appID, "app-1")
        XCTAssertEqual(fields.accessToken, "tok-2")
        XCTAssertEqual(fields.authMode, .appToken)
        // Custom resource IDs are ignored; product is locked to SAUC 2.0 duration.
        XCTAssertEqual(fields.resourceID, VolcengineASRFields.fixedResourceID)
        XCTAssertTrue(fields.hasUsableCredentials)
    }

    func testVolcengineASRFieldsColonParsing() {
        let fields = VolcengineASRFields.parse(
            apiKey: "app-1:tok-2:res-3",
            resourceFallback: CloudASRModelCatalog.defaultModel(for: "volcengine")
        )
        XCTAssertEqual(fields.appID, "app-1")
        XCTAssertEqual(fields.accessToken, "tok-2")
        XCTAssertEqual(fields.authMode, .appToken)
        XCTAssertEqual(fields.resourceID, VolcengineASRFields.fixedResourceID)
        XCTAssertTrue(fields.encodedAPIKey.contains("app-1"))
        XCTAssertTrue(fields.encodedAPIKey.contains("auth_mode"))
    }

    func testVolcengineASRFieldsAPIKeyModeParsing() {
        let json = #"{"auth_mode":"api_key","api_key":"vk-new-console"}"#
        let fields = VolcengineASRFields.parse(apiKey: json)
        XCTAssertEqual(fields.authMode, .apiKey)
        XCTAssertEqual(fields.apiKeyCredential, "vk-new-console")
        XCTAssertTrue(fields.hasUsableCredentials)
        XCTAssertEqual(fields.resourceID, VolcengineASRFields.fixedResourceID)

        var request = URLRequest(url: URL(string: "wss://example.invalid")!)
        fields.applyWebSocketAuthHeaders(to: &request, connectID: "conn-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "vk-new-console")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-App-Key"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Access-Key"))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Resource-Id"),
            VolcengineASRFields.fixedResourceID
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Connect-Id"), "conn-1")
    }

    func testVolcengineASRFieldsAppTokenHeaders() {
        let fields = VolcengineASRFields(
            authMode: .appToken,
            appID: "app-1",
            accessToken: "tok-2"
        )
        var request = URLRequest(url: URL(string: "wss://example.invalid")!)
        fields.applyWebSocketAuthHeaders(to: &request, connectID: "conn-2")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-App-Key"), "app-1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Access-Key"), "tok-2")
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Api-Key"))
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-Api-Resource-Id"),
            VolcengineASRFields.fixedResourceID
        )
    }

    func testVolcengineASRFieldsTogglePreservesBothCredentialSets() {
        var fields = VolcengineASRFields(
            authMode: .appToken,
            appID: "app-1",
            accessToken: "tok-2",
            apiKeyCredential: "vk-keep"
        )
        fields.authMode = .apiKey
        let encoded = fields.encodedAPIKey
        let parsed = VolcengineASRFields.parse(apiKey: encoded)
        XCTAssertEqual(parsed.authMode, .apiKey)
        XCTAssertEqual(parsed.apiKeyCredential, "vk-keep")
        XCTAssertEqual(parsed.appID, "app-1")
        XCTAssertEqual(parsed.accessToken, "tok-2")
    }

    func testVolcengineASRFieldsEmptyDefaultsToAPIKeyMode() {
        let fields = VolcengineASRFields.parse(apiKey: "")
        XCTAssertEqual(fields.authMode, .apiKey)
        XCTAssertFalse(fields.hasUsableCredentials)
    }

    func testVolcengineASRFieldsEmptyAPIKeyModeIsNotUsable() {
        let json = #"{"auth_mode":"api_key"}"#
        let fields = VolcengineASRFields.parse(apiKey: json)
        XCTAssertEqual(fields.authMode, .apiKey)
        XCTAssertFalse(fields.hasUsableCredentials)
    }

    func testPersonalDictionaryASRHotwordsDedupesTerms() {
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Kubernetes", category: .technical, source: .manual),
            PersonalDictionary.Entry(term: "kubernetes", category: .technical, source: .manual),
            PersonalDictionary.Entry(term: "OSGKeyboard", category: .productName, source: .manual)
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
            PersonalDictionary.Entry(term: "Cursor", category: .productName, source: .manual)
        ])
        let entries = dict.alibabaHotwordEntries()
        // Includes built-in system term "OSGKeyboard" via effectiveEntries.
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains(where: { $0.text == "Cursor" }))
        XCTAssertTrue(entries.contains(where: { $0.text == "OSGKeyboard" }))
        XCTAssertEqual(entries.first(where: { $0.text == "Cursor" })?.weight, 4)
    }

    func testPCMSampleWavEncoderProducesHeader() {
        let wav = PCMSampleWavEncoder.encode(samples: [0.0, 0.5, -0.5], sampleRate: 16_000)
        XCTAssertGreaterThan(wav.count, 44)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: wav.dropFirst(8).prefix(4), encoding: .ascii), "WAVE")
    }

    func testOpenAIRealtimeProbeCancellationDoesNotUseBatchFallback() {
        XCTAssertFalse(
            OpenAIRealtimeASRClient.shouldFallbackToBatch(afterProbeError: CancellationError())
        )
        XCTAssertFalse(
            OpenAIRealtimeASRClient.shouldFallbackToBatch(afterProbeError: URLError(.cancelled))
        )
        XCTAssertTrue(
            OpenAIRealtimeASRClient.shouldFallbackToBatch(
                afterProbeError: CloudASRError.transport("handshake failed")
            )
        )
    }

    func testVocabularyFingerprintChangesWhenDictionaryChanges() {
        let emptyFP = PersonalDictionary.empty.vocabularySyncFingerprint()
        let withTerm = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "Kubernetes", category: .technical, source: .manual)
        ])
        XCTAssertNotEqual(emptyFP, withTerm.vocabularySyncFingerprint())
    }

    private func clearQwenMigrationKeys() {
        try? Keychain.deleteAPIKey(for: "qwen", useICloudSync: true)
        try? Keychain.deleteASRAPIKey(for: "qwen", useICloudSync: true)
        try? Keychain.deleteASRAPIKey(for: "bailian", useICloudSync: true)
    }
}
