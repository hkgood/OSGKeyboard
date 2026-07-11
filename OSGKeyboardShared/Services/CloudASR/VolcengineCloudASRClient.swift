// VolcengineCloudASRClient.swift
// OSGKeyboard · Shared
//
// Volcengine SAUC bigmodel ASR client. The service uses a WebSocket with a
// small custom binary frame wrapper; this file keeps that protocol isolated
// from the HTTP-style cloud ASR clients.

import Foundation

struct VolcengineCloudASRClient: CloudASRTranscribing {
    let apiKey: String
    let endpoint: String
    let resourceID: String
    let session: URLSession

    private static let targetChunkBytes = 6_400 // 200 ms @ 16 kHz, 16-bit, mono.
    private static let finalTimeout: TimeInterval = 12
    private static let hotwordCap = 80

    func prepare(dictionary: PersonalDictionary) async throws {}

    func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        guard !samples.isEmpty else { throw CloudASRError.emptyTranscript }
        let credentials = try VolcengineCredentials.parse(
            apiKey: apiKey,
            fallbackResourceID: resolvedResourceID
        )
        let url = try resolvedEndpointURL()
        let pcm = Self.pcm16Data(samples: samples)
        let connectID = UUID().uuidString

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(credentials.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(credentials.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(credentials.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID, forHTTPHeaderField: "X-Api-Connect-Id")

        let task = session.webSocketTask(with: request)
        task.resume()
        defer {
            task.cancel(with: .normalClosure, reason: nil)
        }

        let firstPayload = try Self.firstFramePayload(connectID: connectID, dictionary: dictionary)
        try await send(
            VolcengineFrame.build(
                messageType: .fullClientRequest,
                flags: .positiveSequence,
                serialization: .json,
                payload: firstPayload,
                sequence: 1
            ),
            task: task
        )

        var sequence = 2
        var offset = 0
        while offset < pcm.count {
            let end = min(offset + Self.targetChunkBytes, pcm.count)
            try await send(
                VolcengineFrame.build(
                    messageType: .audioOnlyRequest,
                    flags: .positiveSequence,
                    serialization: .none,
                    payload: pcm.subdata(in: offset..<end),
                    sequence: Int32(sequence)
                ),
                task: task
            )
            sequence += 1
            offset = end
        }

        try await send(
            VolcengineFrame.build(
                messageType: .audioOnlyRequest,
                flags: .negativeSequence,
                serialization: .none,
                payload: Data(),
                sequence: -Int32(sequence)
            ),
            task: task
        )

        let text = try await receiveFinalText(task: task)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudASRError.emptyTranscript }
        return trimmed
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

    private func send(_ data: Data, task: URLSessionWebSocketTask) async throws {
        do {
            try await task.send(.data(data))
        } catch {
            throw CloudASRError.transport(error.localizedDescription)
        }
    }

    private func receiveFinalText(task: URLSessionWebSocketTask) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                var lastPartial = ""
                while true {
                    let message = try await task.receive()
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
                        throw CloudASRError.transport("ASR error \(code): \(body)")
                    }
                    guard frame.messageType == .fullServerResponse else { continue }
                    let parsedText = Self.text(from: frame.payload)
                    if !parsedText.isEmpty {
                        lastPartial = parsedText
                    }
                    if frame.isFinal {
                        return parsedText.isEmpty ? lastPartial : parsedText
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.finalTimeout * 1_000_000_000))
                throw CloudASRError.transport("Volcengine final result timed out")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func firstFramePayload(
        connectID: String,
        dictionary: PersonalDictionary
    ) throws -> Data {
        var request: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "show_utterances": true,
            "enable_speaker_info": true,
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

    private static func text(from payload: Data) -> String {
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

private enum VolcengineMessageType: UInt8 {
    case fullClientRequest = 0b0001
    case audioOnlyRequest = 0b0010
    case fullServerResponse = 0b1001
    case errorMessage = 0b1111
}

private enum VolcengineFlags: UInt8 {
    case none = 0b0000
    case positiveSequence = 0b0001
    case lastPacket = 0b0010
    case negativeSequence = 0b0011
}

private enum VolcengineSerialization: UInt8 {
    case none = 0b0000
    case json = 0b0001
}

private struct VolcengineFrame {
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
