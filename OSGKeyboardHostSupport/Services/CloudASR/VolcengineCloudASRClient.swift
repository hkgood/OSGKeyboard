// VolcengineCloudASRClient.swift
// OSGKeyboard · Shared
//
// Volcengine SAUC bigmodel ASR client. Utterance-level WebSocket session with
// enable_nonstream (official two-pass): interim text for on-screen partials,
// definite utterances for polish-ready finals.

import Foundation
import os
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

struct VolcengineCloudASRClient: CloudASRTranscribing, CloudASRStreamingCapable {
    let apiKey: String
    let endpoint: String
    let resourceID: String
    let session: URLSession

    static let targetChunkBytes = 6_400 // 200 ms @ 16 kHz, 16-bit, mono.
    static let finalTimeout: TimeInterval = 12
    private static let hotwordCap = 80

    func prepare(dictionary: PersonalDictionary) async throws {}

    func openStreamingSession(
        locale: Locale,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> any CloudASRStreamingSession {
        _ = locale
        let credentials = try VolcengineCredentials.parse(
            apiKey: apiKey,
            fallbackResourceID: resolvedResourceID
        )
        let url = try resolvedEndpointURL()
        let connectID = UUID().uuidString

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(credentials.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(credentials.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(credentials.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")

        let task = session.webSocketTask(with: request)
        task.resume()
        let live = VolcengineStreamingSession(
            wsTask: task,
            connectID: connectID,
            dictionary: dictionary,
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
        _ = sampleRate
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

    /// Settings connection probe: WebSocket upgrade + first-frame auth only.
    ///
    /// Do not push silence through `transcribe` — SAUC returns an empty final
    /// then closes the socket, and `finish()` prefers that Socket error over
    /// `emptyTranscript`, so the default silence probe always failed while
    /// real dictation (with speech) still worked.
    func probeConnection() async throws {
        let live = try await openStreamingSession(
            locale: Locale(identifier: "zh-CN"),
            dictionary: .empty,
            onPartial: { _ in }
        )
        live.cancel()
    }

    private var resolvedResourceID: String {
        resourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CloudASRModelCatalog.volcengineDefaultResourceID
            : resourceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedEndpointURL() throws -> URL {
        let raw = endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CloudASRModelCatalog.volcengineEndpoint
            : endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw) else { throw CloudASRError.invalidURL }
        return url
    }

    static func firstFramePayload(
        connectID: String,
        dictionary: PersonalDictionary
    ) throws -> Data {
        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "show_utterances": true,
            "enable_speaker_info": true,
            // Official two-pass: stream interim for UI, nostream re-decode per
            // VAD sentence for definite polish-ready text (scheme A).
            "enable_nonstream": true,
            "end_window_size": 800,
            "force_to_speech_time": 1_000,
        ]
        if let context = hotwordContext(dictionary: dictionary) {
            request["context"] = context
        }

        let payload: [String: Any] = [
            "user": ["uid": connectID],
            "audio": [
                "format": "pcm",
                "rate": 16_000,
                "bits": 16,
                "channel": 1,
                "codec": "raw",
            ],
            "request": request,
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    private static func hotwordContext(dictionary: PersonalDictionary) -> String? {
        var seen: [String] = []
        for word in dictionary.asrHotwords() {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard !seen.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                continue
            }
            seen.append(trimmed)
            if seen.count >= hotwordCap { break }
        }
        guard !seen.isEmpty else { return nil }
        let words = seen.map { ["word": $0] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["hotwords": words]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func displayText(from payload: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let result = normalizedResult(from: json) else {
            return ""
        }

        if let utterances = result["utterances"] as? [[String: Any]], !utterances.isEmpty {
            let pieces = utterances.compactMap { $0["text"] as? String }
            let joined = pieces.joined()
            if !joined.isEmpty { return joined }
        }
        return result["text"] as? String ?? ""
    }

    /// Prefer definite (two-pass) utterance text for polish input.
    static func committedText(from payload: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let result = normalizedResult(from: json),
              let utterances = result["utterances"] as? [[String: Any]],
              !utterances.isEmpty else {
            return ""
        }
        let definite = utterances.compactMap { utterance -> String? in
            let isDefinite = utterance["definite"] as? Bool ?? false
            guard isDefinite else { return nil }
            return utterance["text"] as? String
        }
        return definite.joined()
    }

    private static func normalizedResult(from json: [String: Any]) -> [String: Any]? {
        if let result = json["result"] as? [String: Any] {
            return result
        }
        if let results = json["result"] as? [[String: Any]] {
            return results.first
        }
        if json["text"] as? String != nil {
            return json
        }
        return nil
    }
}

// MARK: - Utterance session

private final class VolcengineStreamingSession: CloudASRStreamingSession, @unchecked Sendable {
    private let wsTask: URLSessionWebSocketTask
    private let connectID: String
    private let dictionary: PersonalDictionary
    private let onPartial: @Sendable (String) -> Void
    private let lock = OSAllocatedUnfairLock()
    private var sequence: Int32 = 1
    private var pcmBuffer = Data()
    private var receiveTask: Task<Void, Never>?
    private var failure: Error?
    private var finished = false
    private var lastDisplay = ""
    private var lastCommitted = ""
    private var sawServerFinal = false

    init(
        wsTask: URLSessionWebSocketTask,
        connectID: String,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) {
        self.wsTask = wsTask
        self.connectID = connectID
        self.dictionary = dictionary
        self.onPartial = onPartial
    }

    func start() async throws {
        let firstPayload = try VolcengineCloudASRClient.firstFramePayload(
            connectID: connectID,
            dictionary: dictionary
        )
        try await send(
            VolcengineFrame.build(
                messageType: .fullClientRequest,
                flags: .positiveSequence,
                serialization: .json,
                payload: firstPayload,
                sequence: 1
            )
        )
        sequence = 2
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func append(samples: [Float]) async throws {
        try throwIfFailed()
        let pcm = CloudASRStreamingPCM.pcm16LE(samples: samples)
        let (frames, nextSequences): ([Data], [Int32]) = lock.withLock {
            pcmBuffer.append(pcm)
            var frames: [Data] = []
            while pcmBuffer.count >= VolcengineCloudASRClient.targetChunkBytes {
                let frame = pcmBuffer.prefix(VolcengineCloudASRClient.targetChunkBytes)
                frames.append(Data(frame))
                pcmBuffer.removeFirst(VolcengineCloudASRClient.targetChunkBytes)
            }
            let nextSequences: [Int32] = frames.indices.map { _ in
                let seq = sequence
                sequence += 1
                return seq
            }
            return (frames, nextSequences)
        }

        for (frame, seq) in zip(frames, nextSequences) {
            try await send(
                VolcengineFrame.build(
                    messageType: .audioOnlyRequest,
                    flags: .positiveSequence,
                    serialization: .none,
                    payload: frame,
                    sequence: seq
                )
            )
        }
    }

    func finish() async throws -> String {
        try throwIfFailed()
        // Only consume a sequence number when we actually send trailing PCM.
        // Skipping an unused seq (common when length is an exact chunk multiple,
        // e.g. the settings probe's 1 s / 32_000-byte clip) makes the final
        // negative packet mismatch server autoAssignedSequence → error 45000000.
        let trailing = lock.withLock { () -> Data in
            let data = pcmBuffer
            pcmBuffer.removeAll(keepingCapacity: false)
            return data
        }

        if !trailing.isEmpty {
            let endSequence = lock.withLock { () -> Int32 in
                let seq = sequence
                sequence += 1
                return seq
            }
            try await send(
                VolcengineFrame.build(
                    messageType: .audioOnlyRequest,
                    flags: .positiveSequence,
                    serialization: .none,
                    payload: trailing,
                    sequence: endSequence
                )
            )
        }

        let negativeSeq = lock.withLock { () -> Int32 in
            let seq = sequence
            sequence += 1
            return seq
        }
        try await send(
            VolcengineFrame.build(
                messageType: .audioOnlyRequest,
                flags: .negativeSequence,
                serialization: .none,
                payload: Data(),
                sequence: -negativeSeq
            )
        )

        let deadline = Date().addingTimeInterval(VolcengineCloudASRClient.finalTimeout)
        while Date() < deadline {
            try throwIfFailed()
            let snapshot = lock.withLock { (sawServerFinal, lastCommitted, lastDisplay) }
            if snapshot.0 {
                let text = snapshot.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? snapshot.2
                    : snapshot.1
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                cancel()
                if trimmed.isEmpty { throw CloudASRError.emptyTranscript }
                return trimmed
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        cancel()
        throw CloudASRError.transport("Volcengine final result timed out")
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

            let data: Data
            switch message {
            case .data(let payload):
                data = payload
            case .string(let string):
                data = Data(string.utf8)
            @unknown default:
                continue
            }

            guard let frame = VolcengineFrame.parse(data) else { continue }
            if frame.messageType == .errorMessage {
                let body = String(data: frame.payload, encoding: .utf8) ?? ""
                let code = frame.errorCode ?? 0
                publishFailure(CloudASRError.transport("ASR error \(code): \(body)"))
                return
            }
            guard frame.messageType == .fullServerResponse else { continue }

            let display = VolcengineCloudASRClient.displayText(from: frame.payload)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let committed = VolcengineCloudASRClient.committedText(from: frame.payload)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let emit = lock.withLock { () -> String in
                if !display.isEmpty {
                    lastDisplay = display
                }
                if !committed.isEmpty {
                    lastCommitted = committed
                }
                if frame.isFinal {
                    sawServerFinal = true
                }
                return lastDisplay
            }

            if !emit.isEmpty {
                onPartial(emit)
            }
        }
    }

    private func send(_ data: Data) async throws {
        do {
            try await wsTask.send(.data(data))
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    private func throwIfFailed() throws {
        let (error, done) = lock.withLock { (failure, finished) }
        if let error { throw error }
        if done { throw CloudASRError.transport("Volcengine session cancelled") }
    }

    private func publishFailure(_ error: Error) {
        lock.withLock { failure = error }
        cancel()
    }
}

private struct VolcengineCredentials {
    let appID: String
    let accessToken: String
    let resourceID: String

    static func parse(apiKey: String, fallbackResourceID: String) throws -> VolcengineCredentials {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudASRError.noAPIKey }

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let appID = string(json, keys: ["app_id", "appId", "appid"])
            let token = string(json, keys: ["access_token", "accessToken", "token"])
            let resourceID = string(json, keys: ["resource_id", "resourceId", "resource"])
                ?? fallbackResourceID
            guard let appID, let token, !resourceID.isEmpty else { throw CloudASRError.noAPIKey }
            return VolcengineCredentials(appID: appID, accessToken: token, resourceID: resourceID)
        }

        let separators = CharacterSet(charactersIn: ":\n,")
        let parts = trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { throw CloudASRError.noAPIKey }
        let resourceID = parts.count >= 3 ? parts[2] : fallbackResourceID
        return VolcengineCredentials(appID: parts[0], accessToken: parts[1], resourceID: resourceID)
    }

    private static func string(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

enum VolcengineMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case errorMessage = 0b1111
}

enum VolcengineFlags: UInt8 {
    case none = 0b0000
    case positiveSequence = 0b0001
    case lastPacket = 0b0010
    case negativeSequence = 0b0011
}

enum VolcengineSerialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

struct VolcengineFrame {
    let messageType: VolcengineMessageType?
    let flags: UInt8
    let sequence: Int32?
    let errorCode: UInt32?
    let payload: Data

    var isFinal: Bool {
        flags == VolcengineFlags.lastPacket.rawValue
            || flags == VolcengineFlags.negativeSequence.rawValue
            || (sequence ?? 0) < 0
    }

    static func build(
        messageType: VolcengineMessageType,
        flags: VolcengineFlags,
        serialization: VolcengineSerialization,
        payload: Data,
        sequence: Int32?
    ) -> Data {
        var data = Data()
        data.append(0x11)
        data.append((messageType.rawValue << 4) | flags.rawValue)
        data.append(serialization.rawValue << 4)
        data.append(0x00)

        if flags == .positiveSequence || flags == .negativeSequence, let sequence {
            data.appendBE32(UInt32(bitPattern: sequence))
        }
        data.appendBE32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    static func parse(_ data: Data) -> VolcengineFrame? {
        guard data.count >= 8 else { return nil }
        let bytes = [UInt8](data)
        let headerSize = Int(bytes[0] & 0x0F) * 4
        guard headerSize >= 4, data.count >= headerSize + 4 else { return nil }

        let typeRaw = (bytes[1] >> 4) & 0x0F
        let messageType = VolcengineMessageType(rawValue: typeRaw)
        let flags = bytes[1] & 0x0F
        let compression = bytes[2] & 0x0F
        guard compression == 0 else { return nil }

        var offset = headerSize
        var sequence: Int32?
        if flags == VolcengineFlags.positiveSequence.rawValue
            || flags == VolcengineFlags.negativeSequence.rawValue {
            guard let value = data.readBE32(at: offset) else { return nil }
            sequence = Int32(bitPattern: value)
            offset += 4
        }

        if messageType == .errorMessage {
            guard let code = data.readBE32(at: offset),
                  let size = data.readBE32(at: offset + 4) else { return nil }
            offset += 8
            guard data.count >= offset + Int(size) else { return nil }
            return VolcengineFrame(
                messageType: messageType,
                flags: flags,
                sequence: sequence,
                errorCode: code,
                payload: data.subdata(in: offset..<(offset + Int(size)))
            )
        }

        guard let size = data.readBE32(at: offset) else { return nil }
        offset += 4
        guard data.count >= offset + Int(size) else { return nil }
        return VolcengineFrame(
            messageType: messageType,
            flags: flags,
            sequence: sequence,
            errorCode: nil,
            payload: data.subdata(in: offset..<(offset + Int(size)))
        )
    }
}

private extension Data {
    mutating func appendBE32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }

    func readBE32(at offset: Int) -> UInt32? {
        guard count >= offset + 4 else { return nil }
        return self[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
