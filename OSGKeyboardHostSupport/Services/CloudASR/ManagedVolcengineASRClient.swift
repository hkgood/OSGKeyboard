// ManagedVolcengineASRClient.swift
// OSGKeyboard · HostSupport
//
// Account-server managed Volcengine ASR. The client reserves a one-shot
// session over HTTP, streams raw PCM16LE over WebSocket, and consumes only
// forwarded provider result payloads. BYOK clients remain independent.

import Foundation
import os
#if canImport(OSGKeyboardShared)
import OSGKeyboardShared
#endif

/// Supplies a short-lived gateway grant. Account sign-in and grant refresh
/// remain outside the ASR transport so they can be wired without coupling.
public protocol ManagedASRGrantProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

public struct StaticManagedASRGrantProvider: ManagedASRGrantProviding {
    private let token: String

    public init(token: String) {
        self.token = token
    }

    public func accessToken(forceRefresh: Bool) async throws -> String {
        _ = forceRefresh
        return token
    }
}

public struct GatewayCoordinatorASRGrantProvider: ManagedASRGrantProviding {
    private let coordinator: GatewayGrantCoordinator

    public init(coordinator: GatewayGrantCoordinator) {
        self.coordinator = coordinator
    }

    public func accessToken(forceRefresh: Bool) async throws -> String {
        try await coordinator.accessToken(for: .asr, forceRefresh: forceRefresh)
    }
}

/// Stable failures for account-managed ASR. Server messages are intentionally
/// not retained because they are neither stable API identifiers nor safe logs.
public enum ManagedCloudASRError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case grantUnavailable
    case grantRejected
    case insufficientCredits
    case concurrencyLimit
    case sessionCreationFailed(status: Int, code: String)
    case sessionTransportFailed
    case connectTimeout
    case idleTimeout
    case websocketFailed(code: String)
    case invalidResult
    case emptyResult
    case batchFailed(status: Int, code: String)
    case batchTransportFailed

    public var stableCode: String {
        switch self {
        case .invalidConfiguration: return "managed_asr_invalid_configuration"
        case .grantUnavailable: return "managed_asr_grant_unavailable"
        case .grantRejected: return "managed_asr_grant_rejected"
        case .insufficientCredits: return "managed_asr_insufficient_credits"
        case .concurrencyLimit: return "managed_asr_concurrency_limit"
        case .sessionCreationFailed: return "managed_asr_session_creation_failed"
        case .sessionTransportFailed: return "managed_asr_session_transport_failed"
        case .connectTimeout: return "managed_asr_connect_timeout"
        case .idleTimeout: return "managed_asr_idle_timeout"
        case .websocketFailed: return "managed_asr_websocket_failed"
        case .invalidResult: return "managed_asr_invalid_result"
        case .emptyResult: return "managed_asr_empty_result"
        case .batchFailed: return "managed_asr_batch_failed"
        case .batchTransportFailed: return "managed_asr_batch_transport_failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return SharedL10n.string("managed.asr.error.invalidConfiguration")
        case .grantUnavailable:
            return SharedL10n.string("managed.error.grantUnavailable")
        case .grantRejected:
            return SharedL10n.string("managed.error.grantRejected")
        case .insufficientCredits:
            return SharedL10n.string("managed.error.insufficientCredits")
        case .concurrencyLimit:
            return SharedL10n.string("managed.asr.error.concurrencyLimit")
        case .sessionCreationFailed:
            return SharedL10n.string("managed.asr.error.sessionCreation")
        case .sessionTransportFailed:
            return SharedL10n.string("managed.asr.error.transport")
        case .connectTimeout:
            return SharedL10n.string("managed.asr.error.connectTimeout")
        case .idleTimeout:
            return SharedL10n.string("managed.asr.error.idleTimeout")
        case .websocketFailed:
            return SharedL10n.string("managed.asr.error.streaming")
        case .invalidResult:
            return SharedL10n.string("managed.asr.error.invalidResult")
        case .emptyResult:
            return SharedL10n.string("error.asr.noSpeech")
        case .batchFailed:
            return SharedL10n.string("managed.asr.error.batch")
        case .batchTransportFailed:
            return SharedL10n.string("managed.asr.error.transport")
        }
    }
}

enum ManagedASRWebSocketMessage: Sendable, Equatable {
    case data(Data)
    case string(String)
    case closed(code: Int, reason: String?)
}

protocol ManagedASRHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol ManagedASRWebSocket: Sendable {
    func resume()
    func ping() async throws
    func send(_ message: ManagedASRWebSocketMessage) async throws
    func receive() async throws -> ManagedASRWebSocketMessage
    func close()
}

protocol ManagedASRWebSocketFactory: Sendable {
    func makeWebSocket(for request: URLRequest) -> any ManagedASRWebSocket
}

private struct URLSessionManagedASRHTTPClient: ManagedASRHTTPClient {
    let session: URLSession

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ManagedCloudASRError.sessionTransportFailed
        }
        return (data, http)
    }
}

private struct URLSessionManagedASRWebSocketFactory: ManagedASRWebSocketFactory {
    let session: URLSession

    func makeWebSocket(for request: URLRequest) -> any ManagedASRWebSocket {
        URLSessionManagedASRWebSocket(task: session.webSocketTask(with: request))
    }
}

private final class URLSessionManagedASRWebSocket: ManagedASRWebSocket, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func resume() {
        task.resume()
    }

    func ping() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    func send(_ message: ManagedASRWebSocketMessage) async throws {
        switch message {
        case .data(let data):
            try await task.send(.data(data))
        case .string(let string):
            try await task.send(.string(string))
        case .closed:
            throw ManagedCloudASRError.invalidConfiguration
        }
    }

    func receive() async throws -> ManagedASRWebSocketMessage {
        do {
            switch try await task.receive() {
            case .data(let data):
                return .data(data)
            case .string(let string):
                return .string(string)
            @unknown default:
                throw ManagedCloudASRError.invalidResult
            }
        } catch {
            let code = task.closeCode
            guard code != .invalid else { throw error }
            let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
            return .closed(code: code.rawValue, reason: reason)
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

public struct ManagedVolcengineASRClient: CloudASRTranscribing, CloudASRStreamingCapable {
    public static let defaultBaseURL = URL(string: "https://account.osglab.com")!

    private let baseURL: URL
    private let grantProvider: any ManagedASRGrantProviding
    private let httpClient: any ManagedASRHTTPClient
    private let webSocketFactory: any ManagedASRWebSocketFactory
    private let estimatedDurationMillis: Int64
    private let connectTimeout: TimeInterval
    private let requestID: @Sendable () -> String

    public init(
        baseURL: URL = ManagedVolcengineASRClient.defaultBaseURL,
        grantProvider: any ManagedASRGrantProviding,
        session: URLSession = .shared,
        estimatedDurationMillis: Int64 = 210_000,
        connectTimeout: TimeInterval = 8
    ) {
        self.init(
            baseURL: baseURL,
            grantProvider: grantProvider,
            httpClient: URLSessionManagedASRHTTPClient(session: session),
            webSocketFactory: URLSessionManagedASRWebSocketFactory(session: session),
            estimatedDurationMillis: estimatedDurationMillis,
            connectTimeout: connectTimeout,
            requestID: { UUID().uuidString }
        )
    }

    public init(
        baseURL: URL = ManagedVolcengineASRClient.defaultBaseURL,
        grants: GatewayGrantCoordinator,
        session: URLSession = .shared,
        estimatedDurationMillis: Int64 = 210_000,
        connectTimeout: TimeInterval = 8
    ) {
        self.init(
            baseURL: baseURL,
            grantProvider: GatewayCoordinatorASRGrantProvider(coordinator: grants),
            session: session,
            estimatedDurationMillis: estimatedDurationMillis,
            connectTimeout: connectTimeout
        )
    }

    init(
        baseURL: URL,
        grantProvider: any ManagedASRGrantProviding,
        httpClient: any ManagedASRHTTPClient,
        webSocketFactory: any ManagedASRWebSocketFactory,
        estimatedDurationMillis: Int64 = 210_000,
        connectTimeout: TimeInterval = 8,
        requestID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.baseURL = baseURL
        self.grantProvider = grantProvider
        self.httpClient = httpClient
        self.webSocketFactory = webSocketFactory
        self.estimatedDurationMillis = estimatedDurationMillis
        self.connectTimeout = connectTimeout
        self.requestID = requestID
    }

    public func prepare(dictionary: PersonalDictionary) async throws {
        _ = dictionary
    }

    public func openStreamingSession(
        locale: Locale,
        dictionary: PersonalDictionary,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> any CloudASRStreamingSession {
        _ = dictionary
        try validateConfiguration()
        let requestID = requestID()
        var grant = try await resolvedGrant()
        let descriptor: SessionDescriptor
        do {
            descriptor = try await createSession(
                grant: grant,
                requestID: requestID,
                locale: locale
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch ManagedCloudASRError.grantRejected {
            grant = try await resolvedGrant(forceRefresh: true)
            descriptor = try await createSession(
                grant: grant,
                requestID: requestID,
                locale: locale
            )
        }

        let socket: any ManagedASRWebSocket
        do {
            socket = try await connectWebSocket(
                descriptor: descriptor,
                grant: grant,
                requestID: requestID
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            grant = try await resolvedGrant(forceRefresh: true)
            socket = try await connectWebSocket(
                descriptor: descriptor,
                grant: grant,
                requestID: requestID
            )
        }

        let live = ManagedVolcengineASRSession(
            socket: socket,
            maxFrameBytes: descriptor.maxFrameBytes,
            idleTimeout: TimeInterval(descriptor.idleTimeoutMillis) / 1_000,
            onPartial: onPartial
        )
        live.startReceiving()
        return live
    }

    public func transcribe(
        samples: [Float],
        sampleRate: Int,
        locale: Locale,
        dictionary: PersonalDictionary
    ) async throws -> String {
        _ = locale
        _ = dictionary
        guard !samples.isEmpty else { throw ManagedCloudASRError.emptyResult }
        guard sampleRate == 16_000 else { throw ManagedCloudASRError.invalidConfiguration }
        try validateConfiguration()
        let pcm = CloudASRStreamingPCM.pcm16LE(samples: samples)
        let durationMillis = max(
            1,
            Int64((Double(samples.count) / Double(sampleRate) * 1_000).rounded(.up))
        )
        guard durationMillis <= 600_000 else { throw CloudASRError.audioTooLong }
        let requestID = requestID()
        let grant = try await resolvedGrant()
        do {
            return try await transcribeBatch(
                pcm: pcm,
                durationMillis: durationMillis,
                grant: grant,
                requestID: requestID
            )
        } catch ManagedCloudASRError.grantRejected {
            return try await transcribeBatch(
                pcm: pcm,
                durationMillis: durationMillis,
                grant: try await resolvedGrant(forceRefresh: true),
                requestID: requestID
            )
        }
    }

    private func transcribeBatch(
        pcm: Data,
        durationMillis: Int64,
        grant: String,
        requestID: String
    ) async throws -> String {
        let url = try endpointURL(path: "/v1/gateway/asr")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(grant)", forHTTPHeaderField: "Authorization")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue("\(durationMillis)", forHTTPHeaderField: "X-Audio-Duration-Ms")
        request.setValue("pcm", forHTTPHeaderField: "X-Audio-Format")
        request.setValue("raw", forHTTPHeaderField: "X-Audio-Codec")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = pcm

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch where ProviderToolCancellation.matches(error) {
            throw CancellationError()
        } catch let error as ManagedCloudASRError {
            throw error
        } catch {
            throw ManagedCloudASRError.batchTransportFailed
        }
        guard (200..<300).contains(response.statusCode) else {
            throw Self.mapHTTPFailure(
                status: response.statusCode,
                data: data,
                phase: .batch
            )
        }
        return try Self.finalText(from: data)
    }

    private func createSession(
        grant: String,
        requestID: String,
        locale: Locale
    ) async throws -> SessionDescriptor {
        let url = try endpointURL(path: "/v1/gateway/asr/sessions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = connectTimeout
        request.setValue("Bearer \(grant)", forHTTPHeaderField: "Authorization")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CreateSessionRequest(
                language: Self.languageHint(from: locale),
                estimatedDurationMillis: estimatedDurationMillis
            )
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch where ProviderToolCancellation.matches(error) {
            throw CancellationError()
        } catch let error as ManagedCloudASRError {
            throw error
        } catch {
            throw ManagedCloudASRError.sessionTransportFailed
        }
        guard response.statusCode == 201 else {
            throw Self.mapHTTPFailure(
                status: response.statusCode,
                data: data,
                phase: .session
            )
        }
        guard let descriptor = try? JSONDecoder().decode(SessionDescriptor.self, from: data),
              UUID(uuidString: descriptor.sessionId) != nil,
              descriptor.maxFrameBytes > 0,
              descriptor.idleTimeoutMillis > 0 else {
            throw ManagedCloudASRError.invalidResult
        }
        return descriptor
    }

    private func connectWebSocket(
        descriptor: SessionDescriptor,
        grant: String,
        requestID: String
    ) async throws -> any ManagedASRWebSocket {
        let websocketURL = try resolvedWebSocketURL(path: descriptor.websocketPath)
        var request = URLRequest(url: websocketURL)
        request.timeoutInterval = connectTimeout
        request.setValue("Bearer \(grant)", forHTTPHeaderField: "Authorization")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")

        let socket = webSocketFactory.makeWebSocket(for: request)
        socket.resume()
        do {
            try await managedWithTimeout(
                seconds: connectTimeout,
                timeoutError: .connectTimeout
            ) {
                try await socket.ping()
            }
            return socket
        } catch is CancellationError {
            socket.close()
            throw CancellationError()
        } catch let error as ManagedCloudASRError {
            socket.close()
            throw error
        } catch {
            socket.close()
            throw ManagedCloudASRError.sessionTransportFailed
        }
    }

    private func resolvedGrant(forceRefresh: Bool = false) async throws -> String {
        let token: String
        do {
            token = try await grantProvider.accessToken(forceRefresh: forceRefresh)
        } catch where ProviderToolCancellation.matches(error) {
            throw CancellationError()
        } catch ManagedGatewayError.insufficientCredits {
            throw ManagedCloudASRError.insufficientCredits
        } catch ManagedGatewayError.invalidGrant {
            throw ManagedCloudASRError.grantRejected
        } catch ManagedGatewayError.scopeNotGranted(_) {
            throw ManagedCloudASRError.grantRejected
        } catch ManagedGatewayError.missingGrant {
            throw ManagedCloudASRError.grantRejected
        } catch {
            throw ManagedCloudASRError.grantUnavailable
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManagedCloudASRError.grantUnavailable }
        return trimmed
    }

    private func validateConfiguration() throws {
        guard baseURL.scheme?.lowercased() == "https",
              baseURL.host != nil,
              estimatedDurationMillis > 0,
              estimatedDurationMillis <= 600_000,
              connectTimeout > 0 else {
            throw ManagedCloudASRError.invalidConfiguration
        }
    }

    private func endpointURL(path: String) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ManagedCloudASRError.invalidConfiguration
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw ManagedCloudASRError.invalidConfiguration
        }
        return url
    }

    private func resolvedWebSocketURL(path: String) throws -> URL {
        // Relative same-origin paths prevent a compromised response from
        // redirecting the bearer grant to another host.
        guard path.hasPrefix("/"),
              !path.hasPrefix("//"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ManagedCloudASRError.invalidResult
        }
        components.scheme = "wss"
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw ManagedCloudASRError.invalidResult }
        return url
    }

    private static func languageHint(from locale: Locale) -> String? {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") { return "zh" }
        if identifier.hasPrefix("en") { return "en" }
        if identifier.hasPrefix("ja") { return "ja" }
        if identifier.hasPrefix("ko") { return "ko" }
        return nil
    }

    private static func finalText(from data: Data) throws -> String {
        var latestDisplay = ""
        var latestCommitted = ""
        var parsedAny = false
        for payload in resultPayloads(from: data) {
            parsedAny = true
            let display = VolcengineCloudASRClient.displayText(from: payload)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let committed = VolcengineCloudASRClient.committedText(from: payload)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty { latestDisplay = display }
            if !committed.isEmpty { latestCommitted = committed }
        }
        guard parsedAny else { throw ManagedCloudASRError.invalidResult }
        let final = latestCommitted.isEmpty ? latestDisplay : latestCommitted
        guard !final.isEmpty else { throw ManagedCloudASRError.emptyResult }
        return final
    }

    fileprivate static func resultPayloads(from data: Data) -> [Data] {
        if let frame = VolcengineFrame.parse(data),
           frame.messageType == .fullServerResponse {
            return [frame.payload]
        }
        var payloads: [Data] = []
        for bytes in [UInt8](data).split(separator: 0x0A, omittingEmptySubsequences: true) {
            let payload = Data(bytes)
            if (try? JSONSerialization.jsonObject(with: payload)) != nil {
                payloads.append(payload)
            }
        }
        return payloads
    }

    private static func mapHTTPFailure(
        status: Int,
        data: Data,
        phase: HTTPPhase
    ) -> ManagedCloudASRError {
        let code = gatewayErrorCode(from: data)
        switch code {
        case "insufficient_credits", "insufficient_balance", "credit_balance_insufficient":
            return .insufficientCredits
        case "asr_concurrency_limit":
            return .concurrencyLimit
        case "unauthorized", "gateway_grant_denied":
            return .grantRejected
        default:
            if status == 401 || status == 403 { return .grantRejected }
            if status == 402 || status == 422 { return .insufficientCredits }
            if status == 429 { return .concurrencyLimit }
            switch phase {
            case .session:
                return .sessionCreationFailed(status: status, code: code)
            case .batch:
                return .batchFailed(status: status, code: code)
            }
        }
    }

    private static func gatewayErrorCode(from data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "unknown"
        }
        if let code = json["code"] as? String, !code.isEmpty { return code }
        if let error = json["error"] as? [String: Any],
           let code = error["code"] as? String,
           !code.isEmpty {
            return code
        }
        return "unknown"
    }

    private enum HTTPPhase {
        case session
        case batch
    }

    private struct CreateSessionRequest: Encodable {
        let format = "pcm"
        let codec = "raw"
        let sampleRate = 16_000
        let bits = 16
        let channels = 1
        let language: String?
        let estimatedDurationMillis: Int64
    }

    private struct SessionDescriptor: Decodable {
        let sessionId: String
        let websocketPath: String
        let maxFrameBytes: Int
        let idleTimeoutMillis: Int64
    }
}

private final class ManagedVolcengineASRSession: CloudASRStreamingSession, @unchecked Sendable {
    private struct State {
        var cancelled = false
        var failure: Error?
        var receiveClosed = false
        var endSent = false
        var latestDisplay = ""
        var latestCommitted = ""
        var sawResultPayload = false
    }

    private let socket: any ManagedASRWebSocket
    private let maxFrameBytes: Int
    private let idleTimeout: TimeInterval
    private let onPartial: @Sendable (String) -> Void
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private var receiveTask: Task<Void, Never>?

    init(
        socket: any ManagedASRWebSocket,
        maxFrameBytes: Int,
        idleTimeout: TimeInterval,
        onPartial: @escaping @Sendable (String) -> Void
    ) {
        self.socket = socket
        self.maxFrameBytes = maxFrameBytes
        self.idleTimeout = idleTimeout
        self.onPartial = onPartial
    }

    func startReceiving() {
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func append(samples: [Float]) async throws {
        try throwIfUnavailable()
        let pcm = CloudASRStreamingPCM.pcm16LE(samples: samples)
        guard !pcm.isEmpty else { return }
        var offset = 0
        while offset < pcm.count {
            try throwIfUnavailable()
            let end = min(offset + maxFrameBytes, pcm.count)
            do {
                try await socket.send(.data(pcm.subdata(in: offset..<end)))
            } catch where ProviderToolCancellation.matches(error) {
                throw CancellationError()
            } catch {
                throw ManagedCloudASRError.sessionTransportFailed
            }
            offset = end
        }
    }

    func finish() async throws -> String {
        try throwIfUnavailable()
        let shouldSendEnd = lock.withLock { state -> Bool in
            guard !state.endSent else { return false }
            state.endSent = true
            return true
        }
        if shouldSendEnd {
            do {
                // The server accepts only this exact control frame.
                try await socket.send(.string(#"{"type":"end"}"#))
            } catch where ProviderToolCancellation.matches(error) {
                throw CancellationError()
            } catch {
                throw ManagedCloudASRError.sessionTransportFailed
            }
        }

        while true {
            try throwIfUnavailable()
            let snapshot = lock.withLock {
                ($0.receiveClosed, $0.latestCommitted, $0.latestDisplay)
            }
            if snapshot.0 {
                let result = snapshot.1.isEmpty ? snapshot.2 : snapshot.1
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                cancelTransport()
                guard !trimmed.isEmpty else { throw ManagedCloudASRError.emptyResult }
                return trimmed
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func cancel() {
        let changed = lock.withLock { state -> Bool in
            guard !state.cancelled else { return false }
            state.cancelled = true
            return true
        }
        guard changed else { return }
        cancelTransport()
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            let message: ManagedASRWebSocketMessage
            do {
                message = try await managedWithTimeout(
                    seconds: idleTimeout,
                    timeoutError: .idleTimeout
                ) {
                    try await self.socket.receive()
                }
            } catch is CancellationError {
                if !lock.withLock({ $0.cancelled }) {
                    publishFailure(CancellationError())
                }
                return
            } catch let error as ManagedCloudASRError {
                publishFailure(error)
                return
            } catch {
                publishFailure(ManagedCloudASRError.sessionTransportFailed)
                return
            }

            switch message {
            case .data(let data):
                let payloads = ManagedVolcengineASRClient.resultPayloads(from: data)
                guard !payloads.isEmpty else {
                    publishFailure(ManagedCloudASRError.invalidResult)
                    return
                }
                for payload in payloads {
                    consume(payload: payload)
                }
            case .string(let text):
                guard let data = text.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["type"] as? String == "gateway_error" else {
                    publishFailure(ManagedCloudASRError.invalidResult)
                    return
                }
                let code = json["code"] as? String ?? "unknown"
                let receivedOnlyEmptyResults = lock.withLock {
                    $0.sawResultPayload
                        && $0.latestDisplay.isEmpty
                        && $0.latestCommitted.isEmpty
                }
                publishFailure(
                    receivedOnlyEmptyResults
                        ? ManagedCloudASRError.emptyResult
                        : ManagedCloudASRError.websocketFailed(code: code)
                )
                return
            case .closed(let code, _):
                if code == URLSessionWebSocketTask.CloseCode.normalClosure.rawValue {
                    lock.withLock { $0.receiveClosed = true }
                } else {
                    publishFailure(
                        ManagedCloudASRError.websocketFailed(code: "close_\(code)")
                    )
                }
                return
            }
        }
    }

    private func consume(payload: Data) {
        let display = VolcengineCloudASRClient.displayText(from: payload)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let committed = VolcengineCloudASRClient.committedText(from: payload)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = lock.withLock { state -> String in
            state.sawResultPayload = true
            if !display.isEmpty { state.latestDisplay = display }
            if !committed.isEmpty { state.latestCommitted = committed }
            return state.latestDisplay
        }
        if !partial.isEmpty {
            onPartial(partial)
        }
    }

    private func throwIfUnavailable() throws {
        let snapshot = lock.withLock { ($0.cancelled, $0.failure) }
        if snapshot.0 { throw CancellationError() }
        if let failure = snapshot.1 { throw failure }
    }

    private func publishFailure(_ error: Error) {
        let shouldClose = lock.withLock { state -> Bool in
            guard state.failure == nil, !state.cancelled else { return false }
            state.failure = error
            return true
        }
        if shouldClose {
            socket.close()
        }
    }

    private func cancelTransport() {
        receiveTask?.cancel()
        socket.close()
    }
}

private func managedWithTimeout<T: Sendable>(
    seconds: TimeInterval,
    timeoutError: ManagedCloudASRError,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw timeoutError
        }
        defer { group.cancelAll() }
        guard let value = try await group.next() else {
            throw timeoutError
        }
        return value
    }
}
