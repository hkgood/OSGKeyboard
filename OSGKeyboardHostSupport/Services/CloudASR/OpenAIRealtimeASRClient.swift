// OpenAIRealtimeASRClient.swift
// OSGKeyboard · Shared
//
// OpenAI Realtime transcription (WebSocket). Streams PCM and transcript
// deltas for utterance-level ASR. Batch `/audio/transcriptions` remains the
// fallback path when realtime is unavailable.

import Foundation
import os
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

struct OpenAIRealtimeASRClient: CloudASRTranscribing, CloudASRStreamingCapable {
    let apiKey: String
    let endpoint: String
    let model: String
    let session: URLSession
    /// Used when streaming fails and Flow falls back to chunked batch ASR.
    private let batchClient: PromptCloudASRClient

    static let appendChunkBytes = 4_800 // 100 ms @ 24 kHz / 16-bit mono.
    static let finalTimeout: TimeInterval = 15

    init(
        apiKey: String,
        endpoint: String,
        model: String,
        batchBaseURL: String,
        session: URLSession
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.session = session
        self.batchClient = PromptCloudASRClient(
            providerId: "openai",
            baseURL: batchBaseURL.isEmpty ? "https://api.openai.com/v1" : batchBaseURL,
            apiKey: apiKey,
            model: Self.batchModel(from: model),
            session: session
        )
    }

    func prepare(dictionary: PersonalDictionary) async throws {}

    func openStreamingSession(
        locale: Locale,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> any CloudASRStreamingSession {
        _ = dictionary
        guard !apiKey.isEmpty else { throw CloudASRError.noAPIKey }
        let url = try resolvedEndpointURL()
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )

        let wsTask = session.webSocketTask(with: request)
        wsTask.resume()
        let live = OpenAIRealtimeStreamingSession(
            wsTask: wsTask,
            model: resolvedRealtimeModel,
            locale: locale,
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
        try await batchClient.transcribe(
            samples: samples,
            sampleRate: sampleRate,
            locale: locale,
            dictionary: dictionary
        )
    }

    func probeConnection() async throws {
        do {
            let session = try await openStreamingSession(
                locale: Locale(identifier: "zh-CN"),
                dictionary: .empty,
                onPartial: { _ in }
            )
            session.cancel()
        } catch {
            try await batchClient.probeConnection()
        }
    }

    private var resolvedRealtimeModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.hasPrefix("gpt-4o") || trimmed == "whisper-1" {
            return CloudASRModelCatalog.openAIRealtimeWhisper
        }
        return trimmed
    }

    private func resolvedEndpointURL() throws -> URL {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("wss://") || raw.hasPrefix("ws://") {
            guard let url = URL(string: raw) else { throw CloudASRError.invalidURL }
            return url
        }
        guard let url = URL(string: CloudASRModelCatalog.openAIRealtimeEndpoint) else {
            throw CloudASRError.invalidURL
        }
        return url
    }

    private static func batchModel(from model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("realtime") {
            return CloudASRModelCatalog.openAITranscribe
        }
        return trimmed
    }
}

// MARK: - Utterance session

private final class OpenAIRealtimeStreamingSession: CloudASRStreamingSession, @unchecked Sendable {
    private let wsTask: URLSessionWebSocketTask
    private let model: String
    private let locale: Locale
    private let onPartial: @Sendable (String) -> Void
    private let lock = OSAllocatedUnfairLock()
    private var receiveTask: Task<Void, Never>?
    private var failure: Error?
    private var finished = false
    private var pcmBuffer = Data()
    private var reducer = OpenAIRealtimeTranscriptReducer()
    private var awaitingCommit = false

    init(
        wsTask: URLSessionWebSocketTask,
        model: String,
        locale: Locale,
        onPartial: @escaping @Sendable (String) -> Void
    ) {
        self.wsTask = wsTask
        self.model = model
        self.locale = locale
        self.onPartial = onPartial
    }

    func start() async throws {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
        let language = OpenAIRealtimeTranscriptReducer.languageHint(from: locale)
        var transcription: [String: Any] = [
            "model": model,
            "delay": "low",
        ]
        if let language {
            transcription["language"] = language
        }
        var input: [String: Any] = [
            "format": [
                "type": "audio/pcm",
                "rate": 24_000,
            ],
            "transcription": transcription,
        ]
        input["turn_detection"] = NSNull()
        let update: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": input,
                ],
            ],
        ]
        try await sendJSON(update)
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            try throwIfFailed()
            if lock.withLock({ reducer.sessionReady }) { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        cancel()
        throw CloudASRError.transport("OpenAI realtime session timed out")
    }

    func append(samples: [Float]) async throws {
        try throwIfFailed()
        let upsampled = CloudASRStreamingPCM.upsample16kTo24k(samples)
        let pcm = CloudASRStreamingPCM.pcm16LE(samples: upsampled)
        let frames: [Data] = lock.withLock {
            pcmBuffer.append(pcm)
            var frames: [Data] = []
            while pcmBuffer.count >= OpenAIRealtimeASRClient.appendChunkBytes {
                let frame = pcmBuffer.prefix(OpenAIRealtimeASRClient.appendChunkBytes)
                frames.append(Data(frame))
                pcmBuffer.removeFirst(OpenAIRealtimeASRClient.appendChunkBytes)
            }
            return frames
        }
        for frame in frames {
            try await sendAppend(frame)
        }
    }

    func finish() async throws -> String {
        try throwIfFailed()
        let trailing: Data = lock.withLock {
            let data = pcmBuffer
            pcmBuffer.removeAll(keepingCapacity: false)
            awaitingCommit = true
            return data
        }
        if !trailing.isEmpty {
            try await sendAppend(trailing)
        }
        try await sendJSON(["type": "input_audio_buffer.commit"])

        let deadline = Date().addingTimeInterval(OpenAIRealtimeASRClient.finalTimeout)
        while Date() < deadline {
            try throwIfFailed()
            let snapshot = lock.withLock {
                (awaitingCommit, reducer.composedFinal(), reducer.composedDisplay())
            }
            if !snapshot.0 {
                let text = snapshot.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? snapshot.2
                    : snapshot.1
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                cancel()
                if trimmed.isEmpty { throw CloudASRError.emptyTranscript }
                return trimmed
            }
            let settled = lock.withLock {
                !reducer.completedByItem.isEmpty && reducer.partialByItem.isEmpty && !awaitingCommit
            }
            if settled {
                let text = lock.withLock { reducer.composedFinal() }
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cancel()
                if text.isEmpty { throw CloudASRError.emptyTranscript }
                return text
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let fallback = lock.withLock {
            let final = reducer.composedFinal()
            return final.isEmpty ? reducer.composedDisplay() : final
        }
        .trimmingCharacters(in: .whitespacesAndNewlines)
        cancel()
        if fallback.isEmpty {
            throw CloudASRError.transport("OpenAI realtime final timed out")
        }
        return fallback
    }

    func cancel() {
        receiveTask?.cancel()
        wsTask.cancel(with: .normalClosure, reason: nil)
        lock.withLock { finished = true }
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await wsTask.receive()
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

            let effect = lock.withLock { () -> OpenAIRealtimeEventEffect in
                let effect = reducer.apply(jsonText: text)
                if case .partial = effect, !reducer.completedByItem.isEmpty {
                    awaitingCommit = false
                }
                return effect
            }
            switch effect {
            case .none, .sessionReady:
                continue
            case .partial(let display):
                onPartial(display)
            case .failed(let message):
                publishFailure(CloudASRError.transport(message))
                return
            }
        }
    }

    private func sendAppend(_ pcm: Data) async throws {
        let audio = pcm.base64EncodedString()
        try await sendJSON([
            "type": "input_audio_buffer.append",
            "audio": audio,
        ])
    }

    private func sendJSON(_ body: [String: Any]) async throws {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let string = String(data: data, encoding: .utf8) else {
            throw CloudASRError.decoding("invalid realtime payload")
        }
        do {
            try await wsTask.send(.string(string))
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    private func throwIfFailed() throws {
        let (error, done) = lock.withLock { (failure, finished) }
        if let error { throw error }
        if done { throw CloudASRError.transport("OpenAI realtime session cancelled") }
    }

    private func publishFailure(_ error: Error) {
        lock.withLock { failure = error }
        cancel()
    }
}
