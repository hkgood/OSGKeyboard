// CloudASRServiceTests.swift
// OSGKeyboardTests

import os
@testable import OSGKeyboardHostSupport
@testable import OSGKeyboardShared
import XCTest

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

private final class RecordingStreamingSession: CloudASRStreamingSession, @unchecked Sendable {
    private let onPartial: @Sendable (String) -> Void
    /// Models a transport the gateway already closed (e.g. idle timeout).
    private let isDead: Bool

    init(onPartial: @escaping @Sendable (String) -> Void, isDead: Bool = false) {
        self.onPartial = onPartial
        self.isDead = isDead
    }

    var acceptsAudio: Bool { !isDead }

    func append(samples: [Float]) async throws {
        if isDead { throw ManagedCloudASRError.idleTimeout }
        if !samples.isEmpty {
            onPartial("你好")
        }
    }

    func finish() async throws -> String {
        if isDead { throw ManagedCloudASRError.idleTimeout }
        return "你好"
    }

    func cancel() {}
}

/// Sessions are numbered by open order, starting at 1.
private final class RecordingStreamingClient: CloudASRStreamingCapable, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    private let deadSessions: Set<Int>
    private let failingOpens: Set<Int>

    init(deadSessions: Set<Int> = [], failingOpens: Set<Int> = []) {
        self.deadSessions = deadSessions
        self.failingOpens = failingOpens
    }

    var openCount: Int {
        lock.withLock { $0 }
    }

    func prepare(dictionary: PersonalDictionary) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        "batch"
    }

    func openStreamingSession(
        locale: Locale,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> any CloudASRStreamingSession {
        _ = locale
        _ = dictionary
        let index = lock.withLock { count -> Int in
            count += 1
            return count
        }
        if failingOpens.contains(index) {
            throw ManagedCloudASRError.sessionTransportFailed
        }
        return RecordingStreamingSession(
            onPartial: onPartial,
            isDead: deadSessions.contains(index)
        )
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

    func testManagedStreamingAdoptsPrimedSession() async {
        let client = RecordingStreamingClient()
        let service = makeManagedService(client: client)
        service.primeUtteranceStreaming(locale: zhLocale)

        let partials = OSAllocatedUnfairLock(initialState: [String]())
        let outcome = await service.transcribeUtteranceStreaming(
            stream: oneSnapshotStream(),
            locale: zhLocale
        ) { partial in
            partials.withLock { $0.append(partial) }
        }

        guard case .success(let success) = outcome else {
            return XCTFail("expected streaming success, got \(outcome)")
        }
        XCTAssertEqual(success.text, "你好")
        XCTAssertEqual(partials.withLock { $0 }, ["你好"])
        XCTAssertEqual(client.openCount, 1)
    }

    func testDeadPrimedSessionIsReplacedWithFreshSession() async {
        let client = RecordingStreamingClient(deadSessions: [1])
        let service = makeManagedService(client: client)
        service.primeUtteranceStreaming(locale: zhLocale)
        await waitUntil { client.openCount == 1 }

        let outcome = await service.transcribeUtteranceStreaming(
            stream: oneSnapshotStream(),
            locale: zhLocale
        ) { _ in }

        guard case .success(let success) = outcome else {
            return XCTFail("expected fresh streaming success, got \(outcome)")
        }
        XCTAssertEqual(success.text, "你好")
        XCTAssertEqual(client.openCount, 2)
    }

    func testExpiredPrimedSessionIsNotAdopted() async {
        let client = RecordingStreamingClient(deadSessions: [1])
        let service = makeManagedService(client: client, primedSessionMaxAge: .zero)
        service.primeUtteranceStreaming(locale: zhLocale)
        await waitUntil { client.openCount == 1 }

        let outcome = await service.transcribeUtteranceStreaming(
            stream: oneSnapshotStream(),
            locale: zhLocale
        ) { _ in }

        guard case .success(let success) = outcome else {
            return XCTFail("expected fresh streaming success, got \(outcome)")
        }
        XCTAssertEqual(success.text, "你好")
        XCTAssertEqual(client.openCount, 2)
    }

    func testFailedPrimeOpensFreshStreamingSession() async {
        let client = RecordingStreamingClient(failingOpens: [1])
        let service = makeManagedService(client: client)
        service.primeUtteranceStreaming(locale: zhLocale)

        let outcome = await service.transcribeUtteranceStreaming(
            stream: oneSnapshotStream(),
            locale: zhLocale
        ) { _ in }

        // "你好" comes from streaming; the chunked batch fallback returns "batch".
        guard case .success(let success) = outcome else {
            return XCTFail("expected fresh streaming success, got \(outcome)")
        }
        XCTAssertEqual(success.text, "你好")
        XCTAssertEqual(client.openCount, 2)
    }

    func testStreamingUtteranceClearsCancellationForBatchFallback() async {
        let client = RecordingStreamingClient()
        let service = makeManagedService(client: client)
        service.cancel()

        _ = await service.transcribeUtteranceStreaming(
            stream: oneSnapshotStream(),
            locale: zhLocale
        ) { _ in }
        let batch = await service.transcribeChunk(
            samples: [Float](repeating: 0.1, count: 1_600),
            locale: zhLocale
        )

        guard case .success(let text) = batch else {
            return XCTFail("expected batch success after a new utterance, got \(batch)")
        }
        XCTAssertEqual(text, "batch")
    }

    // MARK: - Helpers

    private let zhLocale = Locale(identifier: "zh-Hans")

    private func makeManagedService(
        client: RecordingStreamingClient,
        primedSessionMaxAge: Duration = CloudASRService.defaultPrimedSessionMaxAge
    ) -> CloudASRService {
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        config.engineMode = "cloud"
        config.credentialSource = .managed
        config.save(to: defaults)
        store = AppGroupStore(defaults: defaults)
        return CloudASRService(
            store: store,
            session: .shared,
            localFallback: RecordingFallbackASR(),
            managedClient: client,
            primedSessionMaxAge: primedSessionMaxAge
        )
    }

    private func oneSnapshotStream() -> AsyncStream<AudioBufferSnapshot> {
        let (stream, continuation) = AsyncStream<AudioBufferSnapshot>.makeStream()
        continuation.yield(
            AudioBufferSnapshot(
                samples: [Float](repeating: 0.1, count: 1_600),
                sampleRate: 16_000
            )
        )
        continuation.finish()
        return stream
    }

    /// Lets the detached prime task run before the utterance starts.
    private func waitUntil(_ condition: () -> Bool) async {
        var attempts = 0
        while !condition(), attempts < 200 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
