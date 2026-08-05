// CloudASRHTTPClientTests.swift
// OSGKeyboardTests
//
// Hermetic HTTP batch Cloud ASR clients (URLProtocol stub; no live network).

import XCTest
@testable import OSGKeyboardShared
@testable import OSGKeyboardHostSupport

final class CloudASRHTTPClientTests: XCTestCase {

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testZhipuTranscribeDecodesTextAndIncludesHotwords() async throws {
        StubURLProtocolStorage.config = (
            200,
            Data(#"{"text":"转写结果"}"#.utf8)
        )
        let session = StubURLProtocol.makeEphemeralSession()
        let client = ZhipuCloudASRClient(
            apiKey: "sk-test",
            model: "glm-asr-2512",
            session: session
        )
        let dict = PersonalDictionary(entries: [
            PersonalDictionary.Entry(term: "OSGKeyboard", category: .productName, source: .manual),
        ])
        // 0.1 s @ 16 kHz
        let samples = [Float](repeating: 0.01, count: 1_600)
        let text = try await client.transcribe(
            samples: samples,
            sampleRate: 16_000,
            locale: Locale(identifier: "zh-Hans"),
            dictionary: dict
        )
        XCTAssertEqual(text, "转写结果")
        let body = try XCTUnwrap(StubURLProtocolStorage.lastRequest?.httpBody)
        // Multipart includes binary WAV — search ASCII markers in raw bytes.
        let hotwordsMarker = Data("name=\"hotwords\"".utf8)
        let termMarker = Data("OSGKeyboard".utf8)
        XCTAssertTrue(body.range(of: hotwordsMarker) != nil)
        XCTAssertTrue(body.range(of: termMarker) != nil)
    }

    func testZhipuTranscribeMaps401ToCloudASRErrorHTTP() async {
        StubURLProtocolStorage.config = (401, Data("Unauthorized".utf8))
        let session = StubURLProtocol.makeEphemeralSession()
        let client = ZhipuCloudASRClient(
            apiKey: "sk-bad",
            model: "glm-asr-2512",
            session: session
        )
        do {
            _ = try await client.transcribe(
                samples: [Float](repeating: 0, count: 1_600),
                sampleRate: 16_000,
                locale: Locale(identifier: "zh-Hans"),
                dictionary: PersonalDictionary()
            )
            XCTFail("expected http error")
        } catch let error as CloudASRError {
            guard case .http(let status, _) = error else {
                return XCTFail("expected .http, got \(error)")
            }
            XCTAssertEqual(status, 401)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testPromptCloudASRRejectsAudioLongerThan30SecondsForGroq() async {
        let session = StubURLProtocol.makeEphemeralSession()
        let client = PromptCloudASRClient(
            providerId: "groq",
            baseURL: "https://api.groq.com/openai/v1",
            apiKey: "sk-test",
            model: "whisper-large-v3-turbo",
            session: session
        )
        // 31 s @ 16 kHz — must fail before any network call.
        let samples = [Float](repeating: 0, count: 16_000 * 31)
        do {
            _ = try await client.transcribe(
                samples: samples,
                sampleRate: 16_000,
                locale: Locale(identifier: "en-US"),
                dictionary: PersonalDictionary()
            )
            XCTFail("expected audioTooLong")
        } catch let error as CloudASRError {
            XCTAssertEqual(error, .audioTooLong)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertNil(StubURLProtocolStorage.lastRequest)
    }

    func testOpenRouterJsonTranscribeSendsApplicationJSON() async throws {
        StubURLProtocolStorage.config = (
            200,
            Data(#"{"text":"hello world"}"#.utf8)
        )
        let session = StubURLProtocol.makeEphemeralSession()
        let client = PromptCloudASRClient(
            providerId: "openrouter",
            baseURL: "https://openrouter.ai/api/v1",
            apiKey: "sk-or",
            model: "openai/whisper-large-v3-turbo",
            session: session,
            requestFormat: .openRouterJson
        )
        let text = try await client.transcribe(
            samples: [Float](repeating: 0.1, count: 1_600),
            sampleRate: 16_000,
            locale: Locale(identifier: "en-US"),
            dictionary: PersonalDictionary()
        )
        XCTAssertEqual(text, "hello world")
        let request = try XCTUnwrap(StubURLProtocolStorage.lastRequest)
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertNotNil(json["input_audio"])
        XCTAssertEqual(json["model"] as? String, "openai/whisper-large-v3-turbo")
    }

    func testUnsupportedCloudASRClientThrowsProviderUnsupported() async {
        let client = UnsupportedCloudASRClient(providerId: "unknown-provider")
        do {
            _ = try await client.transcribe(
                samples: [0.1],
                sampleRate: 16_000,
                locale: Locale(identifier: "en-US"),
                dictionary: PersonalDictionary()
            )
            XCTFail("expected providerUnsupported")
        } catch let error as CloudASRError {
            XCTAssertEqual(error, .providerUnsupported)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testCloudASRClientFactoryRoutesVolcengineAndLocalFallbackProviders() {
        let suite = "group.com.osgkeyboard.tests.cloud-factory.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.engineMode = "cloud"
        config.asrProviderId = "volcengine"
        config.save(to: defaults)
        let store = AppGroupStore(defaults: defaults)
        XCTAssertTrue(CloudASRClientFactory.make(store: store) is VolcengineCloudASRClient)

        config.asrProviderId = "moonshot"
        config.save(to: defaults)
        let moonshotStore = AppGroupStore(defaults: defaults)
        XCTAssertTrue(
            CloudASRClientFactory.make(store: moonshotStore) is UnsupportedCloudASRClient
        )
        XCTAssertEqual(
            CloudASRModelCatalog.strategy(for: moonshotStore.asrProviderId),
            .localFallback
        )
    }

    func testVolcengineProbeConnectionRejectsEmptyAPIKey() async {
        let client = VolcengineCloudASRClient(
            apiKey: "",
            endpoint: "",
            resourceID: CloudASRModelCatalog.volcengineDefaultResourceID,
            session: .shared
        )
        do {
            try await client.probeConnection()
            XCTFail("expected noAPIKey")
        } catch let error as CloudASRError {
            XCTAssertEqual(error, .noAPIKey)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
