// CloudASRStreamingEventParsing.swift
// OSGKeyboard · HostSupport
//
// Pure reducers for streaming ASR WebSocket event JSON — hermetic fixtures
// without a live socket.

import Foundation
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

// MARK: - Bailian Fun-ASR Realtime

enum BailianASREventEffect: Equatable, Sendable {
    case none
    case started
    case partial(String)
    case finished(String)
    case failed(String)
}

struct BailianASREventReducer: Sendable {
    private(set) var finalSegments: [Int64: String] = [:]
    private(set) var partialSegments: [Int64: String] = [:]
    private(set) var lastResultText = ""
    private(set) var started = false

    mutating func apply(jsonText: String) -> BailianASREventEffect {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .none
        }
        return apply(json: json)
    }

    mutating func apply(json: [String: Any]) -> BailianASREventEffect {
        guard let header = json["header"] as? [String: Any] else { return .none }
        let event = header["event"] as? String ?? ""

        switch event {
        case "task-started":
            started = true
            return .started
        case "result-generated":
            return applyResultGenerated(json: json)
        case "task-finished":
            if finalSegments.isEmpty {
                return .finished(lastResultText)
            }
            let ordered = finalSegments.keys.sorted().compactMap { finalSegments[$0] }
            return .finished(BailianRealtimeASRClient.mergeSegments(ordered))
        case "task-failed":
            let message = header["error_message"] as? String ?? "task failed"
            return .failed(message)
        default:
            return .none
        }
    }

    private mutating func applyResultGenerated(json: [String: Any]) -> BailianASREventEffect {
        guard let payload = json["payload"] as? [String: Any],
              let output = payload["output"] as? [String: Any],
              let sentenceObj = output["sentence"] as? [String: Any] else {
            return .none
        }
        if sentenceObj["heartbeat"] as? Bool == true { return .none }
        guard let rawText = sentenceObj["text"] as? String else { return .none }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }

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

        var displayParts: [String] = []
        let ids = Set(finalSegments.keys).union(partialSegments.keys).sorted()
        for id in ids {
            if let committed = finalSegments[id] {
                displayParts.append(committed)
            } else if let live = partialSegments[id] {
                displayParts.append(live)
            }
        }
        let display = BailianRealtimeASRClient.mergeSegments(displayParts)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return display.isEmpty ? .none : .partial(display)
    }
}

// MARK: - OpenAI Realtime transcription

enum OpenAIRealtimeEventEffect: Equatable, Sendable {
    case none
    case sessionReady
    case partial(String)
    case failed(String)
}

struct OpenAIRealtimeTranscriptReducer: Sendable {
    private(set) var sessionReady = false
    private(set) var partialByItem: [String: String] = [:]
    private(set) var completedByItem: [String: String] = [:]
    private(set) var itemOrder: [String] = []

    mutating func apply(jsonText: String) -> OpenAIRealtimeEventEffect {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return .none
        }
        return apply(type: type, json: json)
    }

    mutating func apply(type: String, json: [String: Any]) -> OpenAIRealtimeEventEffect {
        switch type {
        case "session.created", "session.updated":
            sessionReady = true
            return .sessionReady
        case "conversation.item.input_audio_transcription.delta":
            let itemID = json["item_id"] as? String ?? "default"
            let delta = json["delta"] as? String ?? ""
            guard !delta.isEmpty else { return .none }
            if partialByItem[itemID] == nil, completedByItem[itemID] == nil {
                itemOrder.append(itemID)
            }
            partialByItem[itemID, default: ""] += delta
            let display = composedDisplay()
            return display.isEmpty ? .none : .partial(display)
        case "conversation.item.input_audio_transcription.completed":
            let itemID = json["item_id"] as? String ?? "default"
            let transcript = (json["transcript"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !itemOrder.contains(itemID) {
                itemOrder.append(itemID)
            }
            if !transcript.isEmpty {
                completedByItem[itemID] = transcript
            }
            partialByItem.removeValue(forKey: itemID)
            let display = composedDisplay()
            return display.isEmpty ? .none : .partial(display)
        case "error":
            let message: String
            if let error = json["error"] as? [String: Any],
               let nested = error["message"] as? String {
                message = nested
            } else {
                message = json["message"] as? String ?? "OpenAI realtime error"
            }
            return .failed(message)
        default:
            return .none
        }
    }

    func composedDisplay() -> String {
        itemOrder.compactMap { id in
            completedByItem[id] ?? partialByItem[id]
        }
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func composedFinal() -> String {
        itemOrder.compactMap { completedByItem[$0] }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func languageHint(from locale: Locale) -> String? {
        let id = locale.identifier.lowercased()
        if id.hasPrefix("zh") { return "zh" }
        if id.hasPrefix("en") { return "en" }
        if id.hasPrefix("ja") { return "ja" }
        if id.hasPrefix("ko") { return "ko" }
        return nil
    }
}
