// FlowSessionBridge.swift
// OSGKeyboard · Shared
//
// TypeWhisper-style Flow session bridge: keyboard writes recording
// signals; host app writes transcription results.

import Foundation

public struct FlowCommand: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case startRecording
        case stopRecording
        case abort
    }

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let action: Action
    public let localeId: String
    public let createdAt: TimeInterval

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        action: Action,
        localeId: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.action = action
        self.localeId = localeId
        self.createdAt = createdAt
    }
}

public struct FlowResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case partial
        case final
        case error
        case aborted
        case timeout
    }

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let status: Status
    public let text: String?
    public let warning: String?
    public let errorKind: FlowSessionKeys.TranscriptionErrorKind?
    public let createdAt: TimeInterval

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        status: Status,
        text: String? = nil,
        warning: String? = nil,
        errorKind: FlowSessionKeys.TranscriptionErrorKind? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.status = status
        self.text = text
        self.warning = warning
        self.errorKind = errorKind
        self.createdAt = createdAt
    }
}

public struct FlowAck: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let consumedAt: TimeInterval

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        consumedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.consumedAt = consumedAt
    }
}

public struct FlowReadySnapshot: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case ready
        case noSession
        case starting
        case audioEngineNotLive
        case waitingForAudioProof
        case recording
        case processing
        case permissionMissing
        case appGroupUnavailable
        case hostLost
        case error
    }

    public let protocolVersion: Int
    public let sessionId: UUID?
    public let ready: Bool
    public let reason: Reason
    public let heartbeatAt: TimeInterval
    public let readyAt: TimeInterval?
    public let audioProofAt: TimeInterval?
    public let engineMode: String
    public let localeId: String
    public let busyUtteranceId: UUID?
    public let sessionExpiresAt: TimeInterval?
    /// Host process generation that wrote this snapshot. A snapshot whose
    /// generation no longer matches `FlowSessionKeys.hostGeneration` was
    /// written by a dead process and is void immediately — no need to wait
    /// out the heartbeat-zombie window. Optional for wire compatibility with
    /// snapshots written before this field existed.
    public let hostGeneration: String?

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID?,
        ready: Bool,
        reason: Reason,
        heartbeatAt: TimeInterval = Date().timeIntervalSince1970,
        readyAt: TimeInterval? = nil,
        audioProofAt: TimeInterval? = nil,
        engineMode: String,
        localeId: String,
        busyUtteranceId: UUID? = nil,
        sessionExpiresAt: TimeInterval? = nil,
        hostGeneration: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.ready = ready
        self.reason = reason
        self.heartbeatAt = heartbeatAt
        self.readyAt = readyAt
        self.audioProofAt = audioProofAt
        self.engineMode = engineMode
        self.localeId = localeId
        self.busyUtteranceId = busyUtteranceId
        self.sessionExpiresAt = sessionExpiresAt
        self.hostGeneration = hostGeneration
    }
}

public struct FlowTranscriptionError: Equatable, Sendable {
    public let message: String
    public let kind: FlowSessionKeys.TranscriptionErrorKind

    public init(message: String, kind: FlowSessionKeys.TranscriptionErrorKind) {
        self.message = message
        self.kind = kind
    }
}

public enum FlowSessionBridge {
    private static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults { return defaults }
        guard let available = AppGroup.defaultsIfAvailable else {
            #if DEBUG
            fatalError("App Group unavailable — inject UserDefaults in tests or fix entitlements.")
            #else
            fatalError("App Group unavailable.")
            #endif
        }
        return available
    }

    /// Force cross-process visibility. Must only be called on the main thread.
    private static func flush(_ store: UserDefaults) {
        if Thread.isMainThread {
            store.synchronize()
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Keyboard/read side: refresh App Group defaults after the extension was
    /// suspended so decisions are not based on stale in-process caches.
    public static func reloadFromDisk(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if Thread.isMainThread {
            store.synchronize()
        }
    }

    // MARK: - Typed Flow protocol

    public static func writeCommand(_ command: FlowCommand, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if let data = encode(command) {
            store.set(data, forKey: FlowSessionKeys.flowCommandPayload)
        }
        flush(store)
        FlowSessionDarwin.postCommandChanged()
    }

    public static func latestCommand(defaults: UserDefaults? = nil) -> FlowCommand? {
        let store = resolvedDefaults(defaults)
        return decode(FlowCommand.self, from: store.data(forKey: FlowSessionKeys.flowCommandPayload))
    }

    public static func writeResult(_ result: FlowResult, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if let data = encode(result) {
            store.set(data, forKey: FlowSessionKeys.flowResultPayload)
        }
        flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    public static func latestResult(defaults: UserDefaults? = nil) -> FlowResult? {
        let store = resolvedDefaults(defaults)
        return decode(FlowResult.self, from: store.data(forKey: FlowSessionKeys.flowResultPayload))
    }

    public static func clearResult(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        flush(store)
    }

    public static func writeAck(_ ack: FlowAck, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if let data = encode(ack) {
            store.set(data, forKey: FlowSessionKeys.flowAckPayload)
        }
        flush(store)
    }

    public static func latestAck(defaults: UserDefaults? = nil) -> FlowAck? {
        let store = resolvedDefaults(defaults)
        return decode(FlowAck.self, from: store.data(forKey: FlowSessionKeys.flowAckPayload))
    }

    public static func writeReadySnapshot(_ snapshot: FlowReadySnapshot, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if let data = encode(snapshot) {
            store.set(data, forKey: FlowSessionKeys.flowReadyPayload)
        }
        if snapshot.ready {
            store.set(true, forKey: FlowSessionKeys.flowHostReady)
            if let readyAt = snapshot.readyAt {
                store.set(readyAt, forKey: FlowSessionKeys.flowHostReadyAt)
            }
        } else {
            // Keep the not-ready payload. The keyboard needs `reason`
            // (recording / processing / waitingForAudioProof / …) to tell
            // "host is busy" apart from "host is still starting". Deleting
            // the payload here forced every mid-utterance ready=false into
            // a permanent orange `preparingSession` state.
            clearHostReady(defaults: store, notify: false)
        }
        if let expires = snapshot.sessionExpiresAt {
            store.set(expires, forKey: FlowSessionKeys.flowSessionExpires)
        }
        // Only a genuinely live host — ready, or actively serving an
        // utterance — may refresh the heartbeat here. A host stuck in a
        // failed cold start would otherwise keep "reviving" itself on every
        // engine-state flap, flickering the keyboard between reachable and
        // dead and postponing zombie-state cleanup indefinitely.
        let provesHostAlive = snapshot.ready
            || snapshot.reason == .recording
            || snapshot.reason == .processing
        if provesHostAlive {
            store.set(snapshot.heartbeatAt, forKey: FlowSessionKeys.flowHeartbeat)
        }
        flush(store)
        FlowSessionDarwin.postHostReadyChanged()
    }

    public static func readySnapshot(defaults: UserDefaults? = nil) -> FlowReadySnapshot? {
        let store = resolvedDefaults(defaults)
        return decode(FlowReadySnapshot.self, from: store.data(forKey: FlowSessionKeys.flowReadyPayload))
    }

    // MARK: - Session lifecycle (host app)

    public static func markSessionActive(
        duration: TimeInterval? = nil,
        sessionId: UUID? = nil,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        let resolvedDuration = duration ?? FlowSessionPolicy.sessionDuration(defaults: store)
        let now = Date().timeIntervalSince1970
        let expires = now + resolvedDuration
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        store.set(expires, forKey: FlowSessionKeys.flowSessionExpires)
        store.set(now, forKey: FlowSessionKeys.lastActivityAt)
        writeHeartbeat(defaults: store)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        if let sessionId {
            let snapshot = FlowReadySnapshot(
                sessionId: sessionId,
                ready: false,
                reason: .starting,
                heartbeatAt: now,
                engineMode: AppGroupConfiguration.load(fromAvailable: store).engineMode,
                localeId: AppGroupConfiguration.load(fromAvailable: store).localeId,
                sessionExpiresAt: expires,
                hostGeneration: store.string(forKey: FlowSessionKeys.hostGeneration)
            )
            if let data = encode(snapshot) {
                store.set(data, forKey: FlowSessionKeys.flowReadyPayload)
            }
        } else {
            store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        }
        flush(store)
    }

    public static func markSessionInactive(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearHostReady(defaults: store, notify: false)
        flush(store)
    }

    public static func writeHeartbeat(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        let now = Date().timeIntervalSince1970
        store.set(now, forKey: FlowSessionKeys.flowHeartbeat)
        if store.bool(forKey: FlowSessionKeys.flowHostReady) {
            store.set(now, forKey: FlowSessionKeys.flowHostReadyAt)
        }
        flush(store)
    }

    public static func extendSession(
        by duration: TimeInterval? = nil,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        let resolvedDuration = duration ?? FlowSessionPolicy.sessionDuration(defaults: store)
        let expires = Date().timeIntervalSince1970 + resolvedDuration
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        store.set(expires, forKey: FlowSessionKeys.flowSessionExpires)
        flush(store)
    }

    /// Resets the inactivity timer after utterance completion or explicit activity.
    public static func touchLastActivity(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        let now = Date().timeIntervalSince1970
        let duration = FlowSessionPolicy.sessionDuration(defaults: store)
        store.set(now, forKey: FlowSessionKeys.lastActivityAt)
        store.set(now + duration, forKey: FlowSessionKeys.flowSessionExpires)
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        flush(store)
    }

    // MARK: - Host return (scheme D)

    public static func setPendingHostBundleId(_ bundleId: String?, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if let bundleId, !bundleId.isEmpty {
            store.set(bundleId, forKey: FlowSessionKeys.pendingHostBundleId)
        } else {
            store.removeObject(forKey: FlowSessionKeys.pendingHostBundleId)
        }
        flush(store)
    }

    public static func pendingHostBundleId(defaults: UserDefaults? = nil) -> String? {
        let store = resolvedDefaults(defaults)
        return store.string(forKey: FlowSessionKeys.pendingHostBundleId)
    }

    public static func clearPendingHostBundleId(defaults: UserDefaults? = nil) {
        setPendingHostBundleId(nil, defaults: defaults)
    }

    // MARK: - Session validity (keyboard)

    /// True when the App Group session contract is still valid (not expired).
    /// Does **not** mean the host can accept utterances — use `isHostReady()`.
    public static func isSessionActive(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        guard store.bool(forKey: FlowSessionKeys.flowSessionActive) else { return false }

        let expires = store.double(forKey: FlowSessionKeys.flowSessionExpires)
        return expires > Date().timeIntervalSince1970
    }

    /// Seconds since the host last wrote `flowHeartbeat`; nil when never written.
    public static func heartbeatStaleness(defaults: UserDefaults? = nil) -> TimeInterval? {
        let store = resolvedDefaults(defaults)
        let heartbeat = store.double(forKey: FlowSessionKeys.flowHeartbeat)
        guard heartbeat > 0 else { return nil }
        return Date().timeIntervalSince1970 - heartbeat
    }

    /// True when the host app recently wrote a heartbeat (foreground or
    /// actively processing). Use for zombie / disconnect detection — **not**
    /// for mic-ready UI; prefer `isHostReady()`.
    public static func isHostReachable(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        guard isSessionActive(defaults: store) else { return false }
        guard let staleness = heartbeatStaleness(defaults: store) else { return false }
        return staleness <= FlowSessionKeys.heartbeatStaleInterval
    }

    // MARK: - Host process generation

    /// Host app: rotate the per-process generation token. Call exactly once,
    /// as early as possible in the host launch path. Returns the previous
    /// generation (nil on first-ever launch) so the caller can log it.
    ///
    /// Rationale: `applicationWillTerminate` is best-effort — it never runs
    /// when a *suspended* app is force-quit (the common case after a failed
    /// cold start). Instead of anchoring cleanup on a termination callback
    /// that may not fire, each launch proves the previous process is dead and
    /// voids whatever session state it left behind.
    @discardableResult
    public static func rotateHostGeneration(defaults: UserDefaults? = nil) -> String? {
        let store = resolvedDefaults(defaults)
        let previous = store.string(forKey: FlowSessionKeys.hostGeneration)
        store.set(UUID().uuidString, forKey: FlowSessionKeys.hostGeneration)
        flush(store)
        return previous
    }

    public static func currentHostGeneration(defaults: UserDefaults? = nil) -> String? {
        let store = resolvedDefaults(defaults)
        return store.string(forKey: FlowSessionKeys.hostGeneration)
    }

    /// Host launch reconciliation: clear every piece of persisted session
    /// state a previous (dead) generation left behind. Unlike
    /// `clearFlowState()` this keeps `pendingHostBundleId` — on a keyboard
    /// `startflow` cold launch the scene delegate stores the host bundle id
    /// *before* the SwiftUI hierarchy (and thus the session manager) exists,
    /// and wiping it here would break the return-to-host affordance.
    public static func clearFlowStateOnHostLaunch(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        store.removeObject(forKey: FlowSessionKeys.keyboardRecordingState)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.audioLevels)
        store.removeObject(forKey: FlowSessionKeys.lastActivityAt)
        clearHostReady(defaults: store, notify: false)
        flush(store)
    }

    // MARK: - Host ready contract (host app → keyboard)

    /// Host app: publish whether Flow can accept a new utterance right now.
    public static func setHostReady(
        _ ready: Bool,
        defaults: UserDefaults? = nil,
        notify: Bool = true
    ) {
        let store = resolvedDefaults(defaults)
        if ready {
            let now = Date().timeIntervalSince1970
            store.set(true, forKey: FlowSessionKeys.flowHostReady)
            store.set(now, forKey: FlowSessionKeys.flowHostReadyAt)
            writeHeartbeat(defaults: store)
        } else {
            clearHostReady(defaults: store, notify: false)
        }
        flush(store)
        if notify {
            FlowSessionDarwin.postHostReadyChanged()
        }
    }

    /// True when the host has published a fresh ready contract (stricter than heartbeat alone).
    public static func isHostReady(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        if let snapshot = readySnapshot(defaults: store) {
            guard snapshot.ready else { return false }
            // Snapshot written by a dead host generation → void immediately,
            // without waiting out the heartbeat-zombie window.
            if let snapshotGeneration = snapshot.hostGeneration,
               let currentGeneration = store.string(forKey: FlowSessionKeys.hostGeneration),
               snapshotGeneration != currentGeneration {
                return false
            }
            guard isHostReachable(defaults: store) else { return false }
            if let readyAt = snapshot.readyAt {
                let skew = abs(snapshot.heartbeatAt - readyAt)
                guard skew <= FlowSessionKeys.hostReadyMaxHeartbeatSkew else { return false }
            }
            return true
        }
        guard isHostReachable(defaults: store) else { return false }
        return store.bool(forKey: FlowSessionKeys.flowHostReady)
    }

    private static func clearHostReady(defaults: UserDefaults, notify: Bool) {
        defaults.removeObject(forKey: FlowSessionKeys.flowHostReady)
        defaults.removeObject(forKey: FlowSessionKeys.flowHostReadyAt)
        if notify {
            FlowSessionDarwin.postHostReadyChanged()
        }
    }

    /// True when the session contract flag is still set but the host heartbeat
    /// proves the process is gone (reboot, force-quit, long suspend).
    public static func isHostStale(
        staleAfter: TimeInterval = FlowSessionKeys.heartbeatZombieInterval,
        defaults: UserDefaults? = nil
    ) -> Bool {
        let store = resolvedDefaults(defaults)
        guard isSessionActive(defaults: store) else { return false }
        guard let staleness = heartbeatStaleness(defaults: store) else { return true }
        return staleness > staleAfter
    }

    /// Clears orphaned App Group Flow state when the host is provably dead.
    @discardableResult
    public static func clearIfHostStale(
        staleAfter: TimeInterval = FlowSessionKeys.heartbeatZombieInterval,
        defaults: UserDefaults? = nil
    ) -> Bool {
        guard isHostStale(staleAfter: staleAfter, defaults: defaults) else { return false }
        clearFlowState(defaults: defaults)
        return true
    }

    public static func sessionExpiresAt(defaults: UserDefaults? = nil) -> TimeInterval? {
        let store = resolvedDefaults(defaults)
        let expires = store.double(forKey: FlowSessionKeys.flowSessionExpires)
        return expires > 0 ? expires : nil
    }

    /// Seconds until session expiry; nil when expired or never started.
    public static func remainingSessionDuration(defaults: UserDefaults? = nil) -> TimeInterval? {
        guard let expires = sessionExpiresAt(defaults: defaults) else { return nil }
        let remaining = expires - Date().timeIntervalSince1970
        return remaining > 0 ? remaining : nil
    }

    // MARK: - Recording signals (keyboard → host)

    public static func setRecordingState(
        _ state: FlowSessionKeys.RecordingState,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        store.set(state.rawValue, forKey: FlowSessionKeys.keyboardRecordingState)
        flush(store)
    }

    public static func recordingState(
        defaults: UserDefaults? = nil
    ) -> FlowSessionKeys.RecordingState {
        let store = resolvedDefaults(defaults)
        let raw = store.string(forKey: FlowSessionKeys.keyboardRecordingState) ?? FlowSessionKeys.RecordingState.idle.rawValue
        return FlowSessionKeys.RecordingState(rawValue: raw) ?? .idle
    }

    public static func setTranscriptionLanguage(
        _ localeId: String,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        store.set(localeId, forKey: FlowSessionKeys.transcriptionLanguage)
        flush(store)
    }

    // MARK: - Results (host → keyboard)

    public static func storeTranscriptionResult(
        _ text: String,
        polishWarning: String? = nil,
        defaults: UserDefaults? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let store = resolvedDefaults(defaults)
        store.set(trimmed, forKey: FlowSessionKeys.transcriptionResult)
        store.removeObject(forKey: FlowSessionKeys.transcriptionError)
        store.removeObject(forKey: FlowSessionKeys.transcriptionPartial)
        if let polishWarning, !polishWarning.isEmpty {
            store.set(polishWarning, forKey: FlowSessionKeys.transcriptionPolishWarning)
        } else {
            store.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        }
        setRecordingState(.idle, defaults: store)
        flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    /// Host app: publish pipelined ASR partial while recording or finalizing.
    public static func storeTranscriptionPartial(
        _ text: String,
        defaults: UserDefaults? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = resolvedDefaults(defaults)
        if trimmed.isEmpty {
            store.removeObject(forKey: FlowSessionKeys.transcriptionPartial)
        } else {
            store.set(trimmed, forKey: FlowSessionKeys.transcriptionPartial)
        }
        flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    /// Keyboard: read the latest partial without clearing it.
    public static func transcriptionPartial(defaults: UserDefaults? = nil) -> String? {
        let store = resolvedDefaults(defaults)
        guard let text = store.string(forKey: FlowSessionKeys.transcriptionPartial),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    public static func storeTranscriptionError(
        _ message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .generic,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        store.set(message, forKey: FlowSessionKeys.transcriptionError)
        store.set(kind.rawValue, forKey: FlowSessionKeys.transcriptionErrorKind)
        setRecordingState(.idle, defaults: store)
        flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    /// Returns and clears a pending transcription result, if any.
    public static func consumeTranscriptionResult(defaults: UserDefaults? = nil) -> String? {
        consumeTranscriptionDelivery(defaults: defaults)?.text
    }

    /// Returns and clears a pending transcription delivery (text + optional
    /// polish warning), if any.
    public static func consumeTranscriptionDelivery(
        defaults: UserDefaults? = nil
    ) -> TranscriptionDelivery? {
        let store = resolvedDefaults(defaults)
        guard let text = store.string(forKey: FlowSessionKeys.transcriptionResult), !text.isEmpty else {
            return nil
        }
        let warning = store.string(forKey: FlowSessionKeys.transcriptionPolishWarning)
        store.removeObject(forKey: FlowSessionKeys.transcriptionResult)
        store.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        flush(store)
        return TranscriptionDelivery(text: text, polishWarning: warning)
    }

    /// Returns and clears a pending transcription error, if any.
    public static func consumeTranscriptionError(defaults: UserDefaults? = nil) -> FlowTranscriptionError? {
        let store = resolvedDefaults(defaults)
        guard let message = store.string(forKey: FlowSessionKeys.transcriptionError), !message.isEmpty else {
            return nil
        }
        let kindRaw = store.string(forKey: FlowSessionKeys.transcriptionErrorKind)
        let kind = FlowSessionKeys.TranscriptionErrorKind(rawValue: kindRaw ?? "") ?? .generic
        store.removeObject(forKey: FlowSessionKeys.transcriptionError)
        store.removeObject(forKey: FlowSessionKeys.transcriptionErrorKind)
        flush(store)
        return FlowTranscriptionError(message: message, kind: kind)
    }

    public static func audioLevels(defaults: UserDefaults? = nil) -> [Float] {
        let store = resolvedDefaults(defaults)
        if let levels = store.array(forKey: FlowSessionKeys.audioLevels) as? [Double], !levels.isEmpty {
            return levels.map { Float($0) }
        }
        if let levels = store.array(forKey: FlowSessionKeys.audioLevels) as? [NSNumber], !levels.isEmpty {
            return levels.map { $0.floatValue }
        }
        return []
    }

    /// Host app: publish waveform bars for the keyboard (main thread only).
    public static func storeAudioLevels(
        _ levels: [Float],
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        store.set(levels.map { Double($0) }, forKey: FlowSessionKeys.audioLevels)
        flush(store)
    }

    /// Clear pending result/error before a new utterance.
    public static func clearPendingTranscription(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        clearTranscription(defaults: store)
        flush(store)
    }

    public static func clearFlowState(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        store.removeObject(forKey: FlowSessionKeys.keyboardRecordingState)
        store.removeObject(forKey: FlowSessionKeys.transcriptionLanguage)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.audioLevels)
        store.removeObject(forKey: FlowSessionKeys.pendingHostBundleId)
        store.removeObject(forKey: FlowSessionKeys.lastActivityAt)
        clearHostReady(defaults: store, notify: false)
        flush(store)
    }

    private static func clearTranscription(defaults: UserDefaults) {
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionResult)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionPartial)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionError)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionErrorKind)
    }
}
