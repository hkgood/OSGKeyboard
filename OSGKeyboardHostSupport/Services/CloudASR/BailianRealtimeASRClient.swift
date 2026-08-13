// BailianRealtimeASRClient.swift
// OSGKeyboard · HostSupport
//
// Alibaba Cloud Bailian / DashScope realtime ASR over the classic inference
// WebSocket (`/api-ws/v1/inference`). Utterance-level duplex session with
// interim `result-generated` partials; batch `transcribe(samples:)` remains
// for connection probes and chunk fallback.

import Foundation
import os
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

struct BailianRealtimeASRClient: CloudASRTranscribing, CloudASRStreamingCapable {
    let apiKey: String
    let endpoint: String
    let model: String
    let vocabularyID: String?
    let session: URLSession

    /// 100 ms of 16 kHz / 16-bit / mono PCM.
    static let targetChunkBytes = 3_200
    static let startTimeout: TimeInterval = 8
    static let finalTimeout: TimeInterval = 12
    private static let sessionTimeout: TimeInterval = startTimeout + finalTimeout + 4

    func prepare(dictionary: PersonalDictionary) async throws {}

    func openStreamingSession(
        locale: Locale,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> any CloudASRStreamingSession {
        _ = locale
        _ = dictionary
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }
        let url = try resolvedEndpointURL()
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CloudASRModelCatalog.alibabaFunASRRealtime
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )

        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()
        let live = BailianStreamingSession(
            wsTask: wsTask,
            model: resolvedModel,
            vocabularyID: vocabularyID,
            onPartial: onPartial
        )
        try await live.start()
        return live
    }

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        guard sampleRate == 16_000 else {
            throw CloudASRError.transport("Bailian realtime expects 16 kHz audio")
        }
        guard !samples.isEmpty else { throw CloudASRError.emptyTranscript }

        let session = try await openStreamingSession(
            locale: locale,
            dictionary: dictionary,
            onPartial: { _ in }
        )
        try await session.append(samples: samples)
        let text = try await session.finish()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudASRError.emptyTranscript }
        return trimmed
    }

    /// Settings connection probe: handshake to `task-started` only.
    func probeConnection() async throws {
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }

        let url = try resolvedEndpointURL()
        let taskID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let resolvedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CloudASRModelCatalog.alibabaFunASRRealtime
            : model.trimmingCharacters(in: .whitespacesAndNewlines)

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )

        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()

        try await withThrowingTaskGroup(of: Void.self) { group in
            let events = BailianEventStream(task: wsTask, onPartial: nil)

            group.addTask {
                defer { events.cancel() }
                try await BailianRealtimeASRClient.sendText(
                    BailianRealtimeASRClient.runTaskMessage(
                        taskID: taskID,
                        model: resolvedModel,
                        vocabularyID: nil
                    ),
                    task: wsTask
                )
                try await events.waitForStarted(timeout: Self.startTimeout)
                try? await BailianRealtimeASRClient.sendText(
                    BailianRealtimeASRClient.finishTaskMessage(taskID: taskID),
                    task: wsTask
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.startTimeout * 1_000_000_000))
                events.cancel()
                wsTask.cancel(with: .goingAway, reason: nil)
                throw CloudASRError.transport("connection probe timed out")
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func resolvedEndpointURL() throws -> URL {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CloudASRModelCatalog.bailianDefaultEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { throw CloudASRError.invalidURL }
        return url
    }

    static func sendText(_ text: String, task: URLSessionWebSocketTask) async throws {
        do {
            try await task.send(.string(text))
        } catch where ProviderToolCancellation.matches(error) {
            throw CancellationError()
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    static func sendBinary(_ data: Data, task: URLSessionWebSocketTask) async throws {
        do {
            try await task.send(.data(data))
        } catch where ProviderToolCancellation.matches(error) {
            throw CancellationError()
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    /// Overlap-aware join to avoid cumulative duplicate text from interim replays.
    static func mergeSegments(_ segments: [String]) -> String {
        var result = ""
        for segment in segments {
            if result.isEmpty {
                result = segment
                continue
            }
            let resultChars = Array(result)
            let segmentChars = Array(segment)
            let maxOverlap = min(resultChars.count, segmentChars.count)
            var overlap = 0
            if maxOverlap >= 2 {
                for length in stride(from: maxOverlap, through: 2, by: -1) {
                    let tail = resultChars.suffix(length)
                    let head = segmentChars.prefix(length)
                    if tail.elementsEqual(head) {
                        overlap = length
                        break
                    }
                }
            }
            result.append(contentsOf: segmentChars.dropFirst(overlap))
        }
        return result
    }

    static func runTaskMessage(taskID: String, model: String, vocabularyID: String?) -> String {
        var parameters: [String: Any] = [
            "sample_rate": 16_000,
            "format": "pcm",
        ]
        if let vocabularyID = vocabularyID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !vocabularyID.isEmpty {
            parameters["vocabulary_id"] = vocabularyID
        }
        let body: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex",
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": parameters,
                "input": [:] as [String: Any],
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func finishTaskMessage(taskID: String) -> String {
        let body: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskID,
                "streaming": "duplex",
            ],
            "payload": ["input": [:] as [String: Any]],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - Utterance session

private final class BailianStreamingSession: CloudASRStreamingSession, @unchecked Sendable {
    private let wsTask: URLSessionWebSocketTask
    private let model: String
    private let vocabularyID: String?
    private let onPartial: @Sendable (String) -> Void
    private let events: BailianEventStream
    private let taskID: String
    private let lock = OSAllocatedUnfairLock()
    private var started = false
    private var pcmBuffer = Data()

    init(
        wsTask: URLSessionWebSocketTask,
        model: String,
        vocabularyID: String?,
        onPartial: @escaping @Sendable (String) -> Void
    ) {
        self.wsTask = wsTask
        self.model = model
        self.vocabularyID = vocabularyID
        self.onPartial = onPartial
        self.taskID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        self.events = BailianEventStream(task: wsTask, onPartial: onPartial)
    }

    func start() async throws {
        try await BailianRealtimeASRClient.sendText(
            BailianRealtimeASRClient.runTaskMessage(
                taskID: taskID,
                model: model,
                vocabularyID: vocabularyID
            ),
            task: wsTask
        )
        try await events.waitForStarted(timeout: BailianRealtimeASRClient.startTimeout)
        lock.withLock { started = true }
    }

    func append(samples: [Float]) async throws {
        guard lock.withLock({ started }) else {
            throw CloudASRError.transport("Bailian session not started")
        }
        let pcm = CloudASRStreamingPCM.pcm16LE(samples: samples)
        let frames: [Data] = lock.withLock {
            pcmBuffer.append(pcm)
            var frames: [Data] = []
            while pcmBuffer.count >= BailianRealtimeASRClient.targetChunkBytes {
                let frame = pcmBuffer.prefix(BailianRealtimeASRClient.targetChunkBytes)
                frames.append(Data(frame))
                pcmBuffer.removeFirst(BailianRealtimeASRClient.targetChunkBytes)
            }
            return frames
        }
        for frame in frames {
            try await BailianRealtimeASRClient.sendBinary(frame, task: wsTask)
        }
    }

    func finish() async throws -> String {
        // Flush remaining PCM (pad short last frame as-is — server tolerates).
        let trailing: Data = lock.withLock {
            let data = pcmBuffer
            pcmBuffer.removeAll(keepingCapacity: false)
            return data
        }
        if !trailing.isEmpty {
            try await BailianRealtimeASRClient.sendBinary(trailing, task: wsTask)
        }
        // Avoid emptyAudio race on very short clips.
        try? await Task.sleep(nanoseconds: 120_000_000)
        try await BailianRealtimeASRClient.sendText(
            BailianRealtimeASRClient.finishTaskMessage(taskID: taskID),
            task: wsTask
        )
        return try await events.waitForFinalText(timeout: BailianRealtimeASRClient.finalTimeout)
    }

    func cancel() {
        events.cancel()
    }
}

// MARK: - Concurrent read loop

private final class BailianEventStream: @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let onPartial: (@Sendable (String) -> Void)?
    private let lock = OSAllocatedUnfairLock()
    private var started = false
    private var finalText: String?
    private var failure: Error?
    private var readTask: Task<Void, Never>?

    init(task: URLSessionWebSocketTask, onPartial: (@Sendable (String) -> Void)?) {
        self.task = task
        self.onPartial = onPartial
        readTask = Task { [weak self] in
            await self?.readLoop()
        }
    }

    func cancel() {
        readTask?.cancel()
        task.cancel(with: .goingAway, reason: nil)
    }

    func waitForStarted(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let failure = snapshotFailure() { throw failure }
            if snapshotStarted() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        cancel()
        throw CloudASRError.transport("task-started timed out")
    }

    func waitForFinalText(timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let failure = snapshotFailure() { throw failure }
            if let text = snapshotFinalText() { return text }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        cancel()
        throw CloudASRError.transport("final result timed out")
    }

    private func snapshotStarted() -> Bool {
        lock.withLock { started }
    }

    private func snapshotFinalText() -> String? {
        lock.withLock { finalText }
    }

    private func snapshotFailure() -> Error? {
        lock.withLock { failure }
    }

    private func readLoop() async {
        var reducer = BailianASREventReducer()

        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                publishFailure(CloudASRError.transport(error.localizedDescription))
                return
            }

            let text: String
            switch message {
            case .string(let value):
                text = value
            case .data(let data):
                text = String(data: data, encoding: .utf8) ?? ""
            @unknown default:
                continue
            }
            guard !text.isEmpty else { continue }

            switch reducer.apply(jsonText: text) {
            case .none:
                continue
            case .started:
                publishStarted()
            case .partial(let display):
                onPartial?(display)
            case .finished(let final):
                publishFinal(final)
                return
            case .failed(let message):
                publishFailure(CloudASRError.transport(message))
                return
            }
        }
    }

    private func publishStarted() {
        lock.withLock { started = true }
    }

    private func publishFinal(_ text: String) {
        lock.withLock { finalText = text }
    }

    private func publishFailure(_ error: Error) {
        lock.withLock { failure = error }
        cancel()
    }
}
