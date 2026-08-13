// LLMStreaming.swift
// OSGKeyboard · Shared
//
// Streaming completion for AI keyboard mode. Dictation polish keeps using
// non-streaming `complete` / `polish`. Visible answer deltas only — reasoning
// / thinking blocks are intentionally ignored.

import Foundation

public enum LLMStreamEvent: Sendable, Equatable {
    /// Incremental visible answer text (append to the draft).
    case delta(String)
    /// Discard the current draft (search-path fallback retry).
    case restart
}

public struct AIAnswerStreamThrottle: Sendable, Equatable {
    public var minInterval: TimeInterval
    public var minCharacterStep: Int

    private var lastPublishedAt: TimeInterval
    private var lastPublishedCount: Int

    public init(
        minInterval: TimeInterval = 0.08,
        minCharacterStep: Int = 24
    ) {
        self.minInterval = minInterval
        self.minCharacterStep = minCharacterStep
        self.lastPublishedAt = 0
        self.lastPublishedCount = 0
    }

    public mutating func shouldPublish(
        accumulatedCount: Int,
        now: TimeInterval = Date().timeIntervalSince1970,
        force: Bool = false
    ) -> Bool {
        if force {
            lastPublishedAt = now
            lastPublishedCount = accumulatedCount
            return true
        }
        let elapsed = now - lastPublishedAt
        let grew = accumulatedCount - lastPublishedCount
        guard lastPublishedAt == 0
            || elapsed >= minInterval
            || grew >= minCharacterStep else {
            return false
        }
        lastPublishedAt = now
        lastPublishedCount = accumulatedCount
        return true
    }
}

// MARK: - SSE transport

enum LLMStreamTransport {
    static func sseJSONPayloads(
        session: URLSession,
        request: URLRequest,
        providerId: String
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.transport("non-HTTP response")
                    }
                    if !(200..<300).contains(http.statusCode) {
                        var responseByteCount = 0
                        for try await _ in bytes {
                            responseByteCount += 1
                        }
                        LLMHTTPDiagnostics.logFailure(
                            providerId: providerId,
                            statusCode: http.statusCode,
                            responseByteCount: responseByteCount,
                            response: http
                        )
                        if http.statusCode == 429 { throw LLMError.rateLimited }
                        throw LLMError.http(status: http.statusCode)
                    }

                    // Accumulate raw UTF-8 bytes — never promote each byte to a
                    // UnicodeScalar, or multi-byte Chinese (etc.) becomes mojibake.
                    var lineBuffer = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == UInt8(ascii: "\n") {
                            if let payload = Self.sseDataPayload(fromLineBytes: lineBuffer) {
                                if payload == Data("[DONE]".utf8) {
                                    break
                                }
                                continuation.yield(payload)
                            }
                            lineBuffer.removeAll(keepingCapacity: true)
                        } else if byte != UInt8(ascii: "\r") {
                            lineBuffer.append(byte)
                        }
                    }
                    if let payload = Self.sseDataPayload(fromLineBytes: lineBuffer),
                       payload != Data("[DONE]".utf8) {
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let urlError as URLError where urlError.code == .cancelled {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMError.transport(String(describing: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Split a complete SSE body into JSON `data:` payloads (UTF-8 safe).
    /// Used by unit tests to lock the line-framing decode path.
    static func sseJSONPayloads(fromBody body: Data) -> [Data] {
        var payloads: [Data] = []
        var lineBuffer = Data()
        for byte in body {
            if byte == UInt8(ascii: "\n") {
                if let payload = sseDataPayload(fromLineBytes: lineBuffer),
                   payload != Data("[DONE]".utf8) {
                    payloads.append(payload)
                }
                lineBuffer.removeAll(keepingCapacity: true)
            } else if byte != UInt8(ascii: "\r") {
                lineBuffer.append(byte)
            }
        }
        if let payload = sseDataPayload(fromLineBytes: lineBuffer),
           payload != Data("[DONE]".utf8) {
            payloads.append(payload)
        }
        return payloads
    }

    /// Decode one SSE line's raw bytes, then extract the `data:` JSON payload.
    static func sseDataPayload(fromLineBytes lineBytes: Data) -> Data? {
        guard let line = String(data: lineBytes, encoding: .utf8) else { return nil }
        return sseDataPayload(from: line)
    }

    /// Returns JSON payload bytes for `data:` SSE lines; nil for comments / event names.
    static func sseDataPayload(from line: String) -> Data? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let raw = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        return Data(raw.utf8)
    }
}

// MARK: - Provider delta parsers

enum LLMStreamDeltaParser {
    /// OpenAI-compatible Chat Completions streaming chunk → visible content delta.
    static func chatCompletionsDelta(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first else {
            return nil
        }
        // Prefer message content; ignore reasoning_content / reasoning fields.
        if let delta = first["delta"] as? [String: Any] {
            if let content = delta["content"] as? String, !content.isEmpty {
                return content
            }
            // Some proxies nest text under delta.text
            if let text = delta["text"] as? String, !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// OpenAI Responses API streaming event → output_text delta only.
    static func responsesOutputTextDelta(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = json["type"] as? String
        if type == "response.output_text.delta",
           let delta = json["delta"] as? String,
           !delta.isEmpty {
            return delta
        }
        // Some gateways mirror Chat Completions shape inside Responses streams.
        if type == nil {
            return chatCompletionsDelta(from: data)
        }
        return nil
    }

    /// Anthropic Messages SSE → text_delta only (skip thinking_delta).
    static func anthropicTextDelta(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let type = json["type"] as? String
        guard type == "content_block_delta",
              let delta = json["delta"] as? [String: Any],
              (delta["type"] as? String) == "text_delta",
              let text = delta["text"] as? String,
              !text.isEmpty else {
            return nil
        }
        return text
    }
}

// MARK: - Stream helpers for clients

enum LLMStreamingSession {
    static func mapSSE(
        session: URLSession,
        request: URLRequest,
        providerId: String,
        parse: @escaping @Sendable (Data) -> String?
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await payload in LLMStreamTransport.sseJSONPayloads(
                        session: session,
                        request: request,
                        providerId: providerId
                    ) {
                        try Task.checkCancellation()
                        if let chunk = parse(payload), !chunk.isEmpty {
                            continuation.yield(.delta(chunk))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMError.transport(String(describing: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
