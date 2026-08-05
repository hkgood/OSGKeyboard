// CloudASRServiceTests.swift
// OSGKeyboardTests

import XCTest
import os
@testable import OSGKeyboardShared
@testable import OSGKeyboardHostSupport

private final class RecordingFallbackASR: ASRService, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)

    var calls: Int {
        lock.withLock { $0 }
    }

    func transcribe(
        stream: AsyncStream<AudioBufferSnapshot>,
        locale: Locale
    ) -> AsyncStream<ASREvent> {
        AsyncStream { $0.finish() }
    }

    func cancel() {}

    func transcribeChunk(samples: [Float], locale: Locale) async -> ASRChunkResult {
        _ = samples
        _ = locale
        lock.withLock { $0 += 1 }
        return .success("local-fallback")
    }
}

final class CloudASRServiceTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: AppGroupStore!

    override func setUp() {
        super.setUp()
        suiteName = "group.com.osgkeyboard.tests.cloud-asr-service.\(UUID().uuidString)"
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

    func testTranscribeChunkRoutesToLocalFallbackForMoonshot() async {
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.engineMode = "cloud"
        config.asrProviderId = "moonshot"
        config.save(to: defaults)
        store = AppGroupStore(defaults: defaults)

        let fallback = RecordingFallbackASR()
        let service = CloudASRService(
            store: store,
            session: .shared,
            localFallback: fallback
        )
        let result = await service.transcribeChunk(
            samples: [Float](repeating: 0.1, count: 1_600),
            locale: Locale(identifier: "zh-Hans")
        )
        guard case .success(let text) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(text, "local-fallback")
        XCTAssertEqual(fallback.calls, 1)
        XCTAssertFalse(service.supportsUtteranceStreaming)
    }

    func testEmptySamplesShortCircuitWithoutFallback() async {
        let fallback = RecordingFallbackASR()
        let service = CloudASRService(
            store: store,
            session: .shared,
            localFallback: fallback
        )
        let result = await service.transcribeChunk(
            samples: [],
            locale: Locale(identifier: "en-US")
        )
        guard case .success(let text) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(text, "")
        XCTAssertEqual(fallback.calls, 0)
    }
}
