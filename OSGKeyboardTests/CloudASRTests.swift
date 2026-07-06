// CloudASRTests.swift
// OSGKeyboardTests

import XCTest
@testable import OSGKeyboardShared

final class CloudASRTests: XCTestCase {

    func testCloudASRStrategyRouting() {
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "zhipu"), .zhipuHotwords)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "qwen"), .alibabaVocabulary)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "openai"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "mimo"), .prompt)
        XCTAssertEqual(CloudASRModelCatalog.strategy(for: "moonshot"), .localFallback)
    }

    func testCloudASRModelDefaults() {
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "qwen"), "fun-asr-flash-2026-06-15")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "zhipu"), "glm-asr-2512")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "mimo"), "mimo-v2.5-asr")
        XCTAssertEqual(CloudASRModelCatalog.defaultModel(for: "openai"), "gpt-4o-mini-transcribe")
    }

    func testPersonalDictionaryCloudASRBadgeProviders() {
        XCTAssertTrue(LLMProvider.provider(id: "zhipu").supportsPersonalDictionaryCloudASR)
        XCTAssertTrue(LLMProvider.provider(id: "qwen").supportsPersonalDictionaryCloudASR)
        XCTAssertFalse(LLMProvider.provider(id: "openai").supportsPersonalDictionaryCloudASR)
        XCTAssertFalse(LLMProvider.provider(id: "moonshot").supportsPersonalDictionaryCloudASR)
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
