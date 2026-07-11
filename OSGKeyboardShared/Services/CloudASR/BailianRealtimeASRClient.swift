// BailianRealtimeASRClient.swift
// OSGKeyboard · Shared
//
// Alibaba Cloud Bailian / DashScope realtime ASR over the classic inference
// WebSocket (`/api-ws/v1/inference`). Matches OpenLess' `bailian.rs` wire
// protocol: run-task → PCM binary frames → finish-task → result events.

import Foundation

struct BailianRealtimeASRClient: CloudASRTranscribing {
    let apiKey: String
    let endpoint: String
    let model: String
    let vocabularyID: String?
    let session: URLSession

    /// 100 ms of 16 kHz / 16-bit / mono PCM.
    private static let targetChunkBytes = 3_200
    private static let startTimeout: TimeInterval = 8
    private static let finalTimeout: TimeInterval = 12
    private static let sessionTimeout: TimeInterval = startTimeout + finalTimeout + 4

    func prepare(dictionary: PersonalDictionary) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }
        guard sampleRate == 16_000 else {
            throw CloudASRError.transport("Bailian realtime expects 16 kHz audio")
        }
        guard !samples.isEmpty else { throw CloudASRError.emptyTranscript }

        let url = try resolvedEndpointURL()
        let pcm = Self.pcm16Data(samples: samples)
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

        return try await withThrowingTaskGroup(of: String.self) { group in
            let events = BailianEventStream(task: wsTask)

            group.addTask {
                defer { events.cancel() }
                return try await Self.runSession(
                    taskID: taskID,
                    model: resolvedModel,
                    pcm: pcm,
                    wsTask: wsTask,
                    events: events
                )
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.sessionTimeout * 1_000_000_000))
                events.cancel()
                wsTask.cancel(with: .goingAway, reason: nil)
                throw CloudASRError.transport("session timed out")
            }

            guard let result = try await group.next() else {
                throw CloudASRError.emptyTranscript
            }
            group.cancelAll()
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Settings connection probe: handshake to `task-started` only.
    ///
    /// Reaching `task-started` proves endpoint + `Authorization` + model are
    /// all valid — which is exactly what "validate connection" must check.
    /// It deliberately sends NO audio: DashScope realtime rejects a short
    /// silent probe with a `task-failed: emptyAudio`, which is a false
    /// negative for a connectivity test. A real auth/quota/model failure
    /// still arrives as `task-failed` before `task-started` and surfaces.
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
            let events = BailianEventStream(task: wsTask)

            group.addTask {
                defer { events.cancel() }
                try await Self.sendText(
                    Self.runTaskMessage(taskID: taskID, model: resolvedModel, vocabularyID: nil),
                    task: wsTask
                )
                try await events.waitForStarted(timeout: Self.startTimeout)
                // Politely end the task; the connection is already proven.
                try? await Self.sendText(Self.finishTaskMessage(taskID: taskID), task: wsTask)
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

    private static func runSession(
        taskID: String,
        model: String,
        pcm: Data,
        wsTask: URLSessionWebSocketTask,
        events: BailianEventStream
    ) async throws -> String {
        try await sendText(
            runTaskMessage(taskID: taskID, model: model, vocabularyID: nil),
            task: wsTask
        )

        try await events.waitForStarted(timeout: startTimeout)

        var offset = 0
        while offset < pcm.count {
            let end = min(offset + targetChunkBytes, pcm.count)
            try await sendBinary(pcm.subdata(in: offset..<end), task: wsTask)
            offset = end
        }

        // Let the server register the final frames before ending the task.
        // Sending `finish-task` in the same instant as the last binary frame
        // races the server's audio buffering (root cause of `emptyAudio` on
        // very short clips).
        try? await Task.sleep(nanoseconds: 120_000_000)

        try await sendText(finishTaskMessage(taskID: taskID), task: wsTask)
        return try await events.waitForFinalText(timeout: finalTimeout)
    }

    private func resolvedEndpointURL() throws -> URL {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CloudASRModelCatalog.bailianDefaultEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { throw CloudASRError.invalidURL }
        return url
    }

    private static func sendText(_ text: String, task: URLSessionWebSocketTask) async throws {
        do {
            try await task.send(.string(text))
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    private static func sendBinary(_ data: Data, task: URLSessionWebSocketTask) async throws {
        do {
            try await task.send(.data(data))
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    private static func pcm16Data(samples: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * 2)
        for sample in samples {
            let scaled = sample * 32_767.0
            let clipped = Swift.max(-32_768.0, Swift.min(32_767.0, scaled))
            var littleEndian = Int16(clipped.rounded()).littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        return data
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

// MARK: - Concurrent read loop

private final class BailianEventStream: @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let lock = NSLock()
    private var started = false
    private var finalText: String?
    private var failure: Error?
    private var readTask: Task<Void, Never>?

    init(task: URLSessionWebSocketTask) {
        self.task = task
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
        lock.lock()
        defer { lock.unlock() }
        return started
    }

    private func snapshotFinalText() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return finalText
    }

    private func snapshotFailure() -> Error? {
        lock.lock()
        defer { lock.unlock() }
        return failure
    }

    private func readLoop() async {
        var finalSegments: [Int64: String] = [:]
        var partialSegments: [Int64: String] = [:]
        var lastResultText = ""

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

            guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let header = json["header"] as? [String: Any] else {
                continue
            }
            let event = header["event"] as? String ?? ""

            switch event {
            case "task-started":
                publishStarted()
            case "result-generated":
                guard let payload = json["payload"] as? [String: Any],
                      let output = payload["output"] as? [String: Any],
                      let sentenceObj = output["sentence"] as? [String: Any] else {
                    continue
                }
                if sentenceObj["heartbeat"] as? Bool == true { continue }
                guard let rawText = sentenceObj["text"] as? String else { continue }
                let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }

                lastResultText = trimmed
                let sentenceID = sentenceObj["sentence_id"] as? Int64 ?? 0
                let sentenceEndValue = sentenceObj["sentence_end"]
                let sentenceEnd = sentenceEndValue as? Bool ?? false
                let endTime = sentenceObj["end_time"] as? Int64 ?? 0
                let isFinal = sentenceEndValue != nil ? sentenceEnd : endTime > 0

                if isFinal {
                    finalSegments[sentenceID] = trimmed
                    partialSegments.removeValue(forKey: sentenceID)
                } else {
                    partialSegments[sentenceID] = trimmed
                }
            case "task-finished":
                if finalSegments.isEmpty {
                    publishFinal(lastResultText)
                } else {
                    let ordered = finalSegments.keys.sorted().compactMap { finalSegments[$0] }
                    publishFinal(BailianRealtimeASRClient.mergeSegments(ordered))
                }
                return
            case "task-failed":
                let message = header["error_message"] as? String ?? "task failed"
                publishFailure(CloudASRError.transport(message))
                return
            default:
                break
            }
        }
    }

    private func publishStarted() {
        lock.lock()
        started = true
        lock.unlock()
    }

    private func publishFinal(_ text: String) {
        lock.lock()
        finalText = text
        lock.unlock()
    }

    private func publishFailure(_ error: Error) {
        lock.lock()
        failure = error
        lock.unlock()
        cancel()
    }
}
