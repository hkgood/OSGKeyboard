// ConfigurationStoreTests.swift
// OSGKeyboardTests
//
// Locks `AppGroupStore` conformance to `ConfigurationStore` and ensures
// pipeline helpers accept the protocol without changing iOS behavior.

import XCTest
@testable import OSGKeyboardShared

final class ConfigurationStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.shared.tests.configuration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        store = AppGroupStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testAppGroupStoreConformsToConfigurationStore() {
        let configuration: any ConfigurationStore = store
        XCTAssertEqual(configuration.cloudASRPersistence, defaults)
        XCTAssertEqual(
            PolishingService.resolvedProviderId(store: configuration, providerIdOverride: nil),
            PolishingService.resolvedProviderId(store: store, providerIdOverride: nil)
        )
    }

    func testASRFactoryAcceptsConfigurationStore() {
        store.setEngineMode("local")
        let service = ASRServiceFactory.make(store: store as any ConfigurationStore)
        XCTAssertTrue(service is SpeechAnalyzerASR)
    }

    func testASRAndPolishProvidersAreIndependent() throws {
        try Keychain.setAPIKey("sk-llm", for: "openai", useICloudSync: false)
        try Keychain.setASRAPIKey("sk-asr", for: "zhipu", useICloudSync: false)

        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.engineMode = "cloud"
        config.providerId = "openai"
        config.asrProviderId = "zhipu"
        config.save(to: defaults)

        let loaded = AppGroupStore(defaults: defaults)
        XCTAssertEqual(loaded.providerId, "openai")
        XCTAssertEqual(loaded.asrProviderId, "zhipu")
        XCTAssertEqual(loaded.apiKey, "sk-llm")
        XCTAssertEqual(loaded.asrApiKey, "sk-asr")

        let asrClient = CloudASRClientFactory.make(store: loaded)
        XCTAssertTrue(asrClient is ZhipuCloudASRClient)
    }

    func testLegacyInstallCopiesProviderIdToAsrProviderId() {
        defaults.set("qwen", forKey: AppGroupConfiguration.Keys.providerId)
        let config = AppGroupConfiguration.load(fromAvailable: defaults)
        XCTAssertEqual(config.asrProviderId, "qwen")
    }
}
