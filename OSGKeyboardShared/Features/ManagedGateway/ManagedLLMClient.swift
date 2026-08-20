// ManagedLLMClient.swift
// OSGKeyboard · Shared
//
// LLMClient implementation for scope-limited managed polish, AI and agent calls.

import Foundation

public struct ManagedLLMClient: LLMClient {
    public enum Capability: String, Sendable {
        case polish
        case assistant = "ai"
        case agent

        var grantScope: ManagedGatewayCapability {
            switch self {
            case .polish: .polish
            case .assistant: .assistant
            case .agent: .agent
            }
        }

        var defaultTaskKind: ManagedGatewayTaskKind {
            switch self {
            case .polish: .dictationPolish
            case .assistant: .aiQuestion
            case .agent: .agentPlanning
            }
        }
    }

    private struct Attempt {
        let input: String
        let context: String?
        let timeout: TimeInterval?
        let options: LLMGenerationOptions
        let requestId: String
        let forceRefresh: Bool

        func forcingRefresh() -> Self {
            Self(
                input: input,
                context: context,
                timeout: timeout,
                options: options,
                requestId: requestId,
                forceRefresh: true
            )
        }
    }

    public let capability: Capability
    public let taskKind: ManagedGatewayTaskKind
    public let requestTimeout: TimeInterval

    private let baseURL: URL
    private let grants: GatewayGrantCoordinator
    private let session: URLSession
    private let requestId: @Sendable () -> String

    public init(
        capability: Capability,
        taskKind: ManagedGatewayTaskKind? = nil,
        grants: GatewayGrantCoordinator,
        baseURL: URL = GatewayGrantCoordinator.defaultBaseURL,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 15,
        requestId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.capability = capability
        self.taskKind = taskKind ?? capability.defaultTaskKind
        self.grants = grants
        self.baseURL = baseURL
        self.session = session
        self.requestTimeout = requestTimeout
        self.requestId = requestId
    }

    public func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?
    ) async throws -> String {
        try await polish(
            text,
            systemPrompt: systemPrompt,
            timeout: timeout,
            options: .polishDefault
        )
    }

    public func polish(
        _ text: String,
        systemPrompt: String,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        try await executeBuffered(
            input: text,
            context: systemPrompt.nilIfEmpty,
            timeout: timeout,
            options: options
        )
    }

    public func complete(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        let payload = Self.payload(from: messages)
        return try await executeBuffered(
            input: payload.input,
            context: payload.context,
            timeout: timeout,
            options: options
        )
    }

    public func completeStreaming(
        messages: [LLMRequest.Message],
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let payload = Self.payload(from: messages)
                    let logicalRequestId = requestId()
                    let attempt = Attempt(
                        input: payload.input,
                        context: payload.context,
                        timeout: timeout,
                        options: options,
                        requestId: logicalRequestId,
                        forceRefresh: false
                    )
                    var emittedVisibleText = false
                    do {
                        try await streamAttempt(attempt) { chunk in
                            emittedVisibleText = true
                            continuation.yield(.delta(chunk))
                        }
                    } catch ManagedGatewayError.invalidGrant where !emittedVisibleText {
                        try await streamAttempt(attempt.forcingRefresh()) { chunk in
                            emittedVisibleText = true
                            continuation.yield(.delta(chunk))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: ManagedGatewayError.timeout)
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch let error as ManagedGatewayError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LLMError.transport(String(describing: error)))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func executeBuffered(
        input: String,
        context: String?,
        timeout: TimeInterval?,
        options: LLMGenerationOptions
    ) async throws -> String {
        let logicalRequestId = requestId()
        let attempt = Attempt(
            input: input,
            context: context,
            timeout: timeout,
            options: options,
            requestId: logicalRequestId,
            forceRefresh: false
        )
        do {
            return try await bufferedAttempt(attempt)
        } catch ManagedGatewayError.invalidGrant {
            do {
                return try await bufferedAttempt(attempt.forcingRefresh())
            } catch ManagedGatewayError.invalidGrant {
                try? await grants.clearGrant()
                throw ManagedGatewayError.invalidGrant
            }
        }
    }

    private func bufferedAttempt(_ attempt: Attempt) async throws -> String {
        let request = try await makeRequest(
            attempt,
            stream: false
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.transport("non-HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw ManagedGatewayHTTP.error(
                    data: data,
                    status: http.statusCode,
                    requestId: attempt.requestId
                )
            }
            return try Self.responseText(from: data)
        } catch is CancellationError {
            throw LLMError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw LLMError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw ManagedGatewayError.timeout
        } catch let error as ManagedGatewayError {
            throw error
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.transport(String(describing: error))
        }
    }

    private func streamAttempt(
        _ attempt: Attempt,
        onDelta: @escaping (String) -> Void
    ) async throws {
        guard capability != .agent else {
            // The server validates agent output as one structured response.
            let text = try await bufferedAttempt(attempt)
            if !text.isEmpty {
                onDelta(text)
            }
            return
        }

        let request = try await makeRequest(
            attempt,
            stream: true
        )
        for try await payload in ManagedGatewayStreamTransport.payloads(
            session: session,
            request: request,
            requestId: attempt.requestId
        ) {
            try Task.checkCancellation()
            if let error = Self.streamingError(from: payload, requestId: attempt.requestId) {
                throw error
            }
            if let delta = Self.streamingDelta(from: payload), !delta.isEmpty {
                onDelta(delta)
            }
        }
    }

    private func makeRequest(_ attempt: Attempt, stream: Bool) async throws -> URLRequest {
        let trimmedInput = attempt.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty, trimmedInput.count <= 32_000 else {
            throw ManagedGatewayError.server(
                code: "invalid_request",
                status: 400,
                requestId: attempt.requestId
            )
        }
        let boundedContext = attempt.context?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        guard (boundedContext?.count ?? 0) <= 32_000 else {
            throw ManagedGatewayError.server(
                code: "invalid_request",
                status: 400,
                requestId: attempt.requestId
            )
        }

        let token = try await grants.accessToken(
            for: capability.grantScope,
            forceRefresh: attempt.forceRefresh
        )
        let body = ManagedGatewayTextRequest(
            input: trimmedInput,
            context: boundedContext,
            maxOutputTokens: min(max(attempt.options.maxTokens ?? 512, 1), 4_096),
            temperature: min(max(attempt.options.temperature ?? 0.2, 0), 1),
            stream: stream,
            taskKind: taskKind
        )

        var request = URLRequest(
            url: baseURL.appending(path: "v1/gateway/llm/\(capability.rawValue)")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(attempt.requestId, forHTTPHeaderField: "X-Request-ID")
        request.timeoutInterval = attempt.timeout ?? requestTimeout
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func payload(
        from messages: [LLMRequest.Message]
    ) -> (input: String, context: String?) {
        guard let inputIndex = messages.lastIndex(where: { $0.role == "user" }) else {
            return ("", Self.contextText(from: messages))
        }
        let input = messages[inputIndex].content
        var contextMessages = messages
        contextMessages.remove(at: inputIndex)
        return (input, Self.contextText(from: contextMessages))
    }

    private static func contextText(from messages: [LLMRequest.Message]) -> String? {
        messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "\($0.role):\n\($0.content)" }
            .joined(separator: "\n\n")
            .nilIfEmpty
    }

    static func responseText(from data: Data) throws -> String {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { throw LLMError.decoding("empty managed gateway response") }
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return raw
        }
        return extractedText(from: json)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? raw
    }

    private static func extractedText(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            let values = array.compactMap(extractedText(from:))
            return values.isEmpty ? nil : values.joined()
        }
        guard let object = value as? [String: Any] else { return nil }

        for key in ["output_text", "text"] {
            if let text = object[key] as? String, !text.isEmpty {
                return text
            }
        }
        if let content = object["content"] {
            if let text = content as? String, !text.isEmpty {
                return text
            }
            if let extracted = extractedText(from: content), !extracted.isEmpty {
                return extracted
            }
        }
        if let message = object["message"] as? [String: Any],
           let extracted = extractedText(from: message) {
            return extracted
        }
        if let choices = object["choices"] as? [[String: Any]],
           let first = choices.first {
            if let message = first["message"] as? [String: Any],
               let extracted = extractedText(from: message) {
                return extracted
            }
            if let text = first["text"] as? String {
                return text
            }
        }
        if let data = object["data"], let extracted = extractedText(from: data) {
            return extracted
        }
        if let output = object["output"], let extracted = extractedText(from: output) {
            return extracted
        }
        return nil
    }

    static func streamingDelta(from data: Data) -> String? {
        if let value = LLMStreamDeltaParser.responsesOutputTextDelta(from: data)
            ?? LLMStreamDeltaParser.chatCompletionsDelta(from: data)
            ?? LLMStreamDeltaParser.anthropicTextDelta(from: data) {
            return value
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        for key in ["delta", "text", "content"] {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func streamingError(
        from data: Data,
        requestId: String
    ) -> ManagedGatewayError? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = object["code"] as? String,
              object["message"] != nil || code.hasSuffix("_error") else {
            return nil
        }
        if ["insufficient_credits", "insufficient_balance"].contains(code) {
            return .insufficientCredits
        }
        if ["unauthorized", "gateway_grant_denied", "invalid_grant"].contains(code) {
            return .invalidGrant
        }
        return .server(code: code, status: 200, requestId: requestId)
    }
}

public enum ManagedGatewayLLMClientFactory {
    public static func polish(
        taskKind: ManagedGatewayTaskKind = .dictationPolish,
        grants: GatewayGrantCoordinator,
        baseURL: URL = GatewayGrantCoordinator.defaultBaseURL,
        session: URLSession = .shared
    ) -> any LLMClient {
        ManagedLLMClient(
            capability: .polish,
            taskKind: taskKind,
            grants: grants,
            baseURL: baseURL,
            session: session
        )
    }

    public static func ai(
        taskKind: ManagedGatewayTaskKind = .aiQuestion,
        grants: GatewayGrantCoordinator,
        baseURL: URL = GatewayGrantCoordinator.defaultBaseURL,
        session: URLSession = .shared
    ) -> any LLMClient {
        ManagedLLMClient(
            capability: .assistant,
            taskKind: taskKind,
            grants: grants,
            baseURL: baseURL,
            session: session
        )
    }

    public static func agent(
        taskKind: ManagedGatewayTaskKind = .agentPlanning,
        grants: GatewayGrantCoordinator,
        baseURL: URL = GatewayGrantCoordinator.defaultBaseURL,
        session: URLSession = .shared
    ) -> any LLMClient {
        ManagedLLMClient(
            capability: .agent,
            taskKind: taskKind,
            grants: grants,
            baseURL: baseURL,
            session: session
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum ManagedGatewayStreamTransport {
    static func payloads(
        session: URLSession,
        request: URLRequest,
        requestId: String
    ) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.transport("non-HTTP response")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                        }
                        throw ManagedGatewayHTTP.error(
                            data: body,
                            status: http.statusCode,
                            requestId: requestId
                        )
                    }

                    let isEventStream = http.value(forHTTPHeaderField: "Content-Type")?
                        .lowercased()
                        .contains("text/event-stream") == true
                    if !isEventStream {
                        var body = Data()
                        for try await byte in bytes {
                            try Task.checkCancellation()
                            body.append(byte)
                        }
                        if !body.isEmpty {
                            continuation.yield(body)
                        }
                        continuation.finish()
                        return
                    }

                    var line = Data()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == UInt8(ascii: "\n") {
                            yieldSSELine(line, to: continuation)
                            line.removeAll(keepingCapacity: true)
                        } else if byte != UInt8(ascii: "\r") {
                            line.append(byte)
                        }
                    }
                    yieldSSELine(line, to: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: LLMError.cancelled)
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: ManagedGatewayError.timeout)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func yieldSSELine(
        _ line: Data,
        to continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        guard let payload = LLMStreamTransport.sseDataPayload(fromLineBytes: line),
              payload != Data("[DONE]".utf8) else {
            return
        }
        continuation.yield(payload)
    }
}
