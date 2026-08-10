// FlowSessionBridge.swift
// OSGKeyboard · Shared
//
// TypeWhisper-style Flow session bridge: keyboard writes recording
// signals; host app writes transcription results.

import Foundation

public struct FlowFieldContext: Codable, Equatable, Sendable {
    public let precedingText: String?
    public let followingText: String?
    public let keyboardType: String?
    public let returnKeyType: String?
    public let isSecureEntry: Bool
    /// Distinguishes a known-empty field from unavailable document context.
    public let isEmptyField: Bool
    public let isContextAvailable: Bool

    public init(
        precedingText: String? = nil,
        followingText: String? = nil,
        keyboardType: String? = nil,
        returnKeyType: String? = nil,
        isSecureEntry: Bool = false,
        isEmptyField: Bool = false,
        isContextAvailable: Bool = false
    ) {
        self.precedingText = isSecureEntry ? nil : precedingText
        self.followingText = isSecureEntry ? nil : followingText
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.isSecureEntry = isSecureEntry
        self.isEmptyField = isSecureEntry ? false : isEmptyField
        self.isContextAvailable = isSecureEntry ? false : isContextAvailable
    }

    public var deliveryFingerprint: String? {
        guard !isSecureEntry else { return nil }
        return [
            keyboardType ?? "",
            returnKeyType ?? "",
            precedingText.map { String($0.suffix(80)) } ?? "",
            followingText.map { String($0.prefix(40)) } ?? "",
        ].joined(separator: "|")
    }
}

public struct FlowCommand: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case startRecording
        case stopRecording
        case abort
        /// Light warm-up: ASR locale/assets only — no mic capture.
        case prewarm
        /// User has touched the mic; prime capture before tap/hold resolves.
        case primeAudio
        /// Touch ended without an utterance adopting the primed capture.
        case cancelPrimeAudio
        /// Remove one temporary AI conversation from host memory.
        case endAIConversation
    }

    /// Wire version that includes temporary AI conversation identifiers.
    public static let currentProtocolVersion = 4

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let action: Action
    public let localeId: String
    public let createdAt: TimeInterval
    public let fieldContext: FlowFieldContext?
    /// Dictation (default) vs explicit edit mode. Absent on legacy v1 → dictation.
    public let utteranceMode: FlowUtteranceMode?
    /// Verified source for explicit last-input editing.
    public let editSourceText: String?
    public let sourceHistoryEntryID: UUID?
    public let sourceHistoryEntryRevision: Int64?
    /// Host-memory conversation used only by `.aiQuestion`.
    public let aiConversationID: UUID?
    /// Absolute wall-clock deadlines survive extension reconstruction.
    public let startDeadlineAt: TimeInterval?
    public let processingDeadlineAt: TimeInterval?

    public init(
        protocolVersion: Int = FlowCommand.currentProtocolVersion,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        action: Action,
        localeId: String,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        fieldContext: FlowFieldContext? = nil,
        utteranceMode: FlowUtteranceMode? = nil,
        editSourceText: String? = nil,
        sourceHistoryEntryID: UUID? = nil,
        sourceHistoryEntryRevision: Int64? = nil,
        aiConversationID: UUID? = nil,
        startDeadlineAt: TimeInterval? = nil,
        processingDeadlineAt: TimeInterval? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.action = action
        self.localeId = localeId
        self.createdAt = createdAt
        self.fieldContext = fieldContext
        self.utteranceMode = utteranceMode
        self.editSourceText = editSourceText
        self.sourceHistoryEntryID = sourceHistoryEntryID
        self.sourceHistoryEntryRevision = sourceHistoryEntryRevision
        self.aiConversationID = aiConversationID
        self.startDeadlineAt = startDeadlineAt
        self.processingDeadlineAt = processingDeadlineAt
    }

    public var resolvedUtteranceMode: FlowUtteranceMode {
        utteranceMode ?? .dictation
    }
}

public struct FlowResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case partial
        case rawReady
        /// AI-mode LLM answer draft (not ASR). Non-terminal.
        case streaming
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
    /// Raw ASR survives polish/network failure and host process churn.
    public let rawText: String?
    public let hostGeneration: String?
    public let revision: Int64?
    public let fieldFingerprint: String?
    public let createdAt: TimeInterval
    /// Echo of the command mode so the extension can skip raw fallback.
    public let utteranceMode: FlowUtteranceMode?
    /// History row created by normal dictation, or edited by edit mode.
    public let historyEntryID: UUID?
    public let historyEntryRevision: Int64?
    /// Echoed for AI result validation; absent for dictation and edit.
    public let aiConversationID: UUID?

    public init(
        protocolVersion: Int = FlowCommand.currentProtocolVersion,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        status: Status,
        text: String? = nil,
        warning: String? = nil,
        errorKind: FlowSessionKeys.TranscriptionErrorKind? = nil,
        rawText: String? = nil,
        hostGeneration: String? = nil,
        revision: Int64? = nil,
        fieldFingerprint: String? = nil,
        createdAt: TimeInterval = Date().timeIntervalSince1970,
        utteranceMode: FlowUtteranceMode? = nil,
        historyEntryID: UUID? = nil,
        historyEntryRevision: Int64? = nil,
        aiConversationID: UUID? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.status = status
        self.text = text
        self.warning = warning
        self.errorKind = errorKind
        self.rawText = rawText
        self.hostGeneration = hostGeneration
        self.revision = revision
        self.fieldFingerprint = fieldFingerprint
        self.createdAt = createdAt
        self.utteranceMode = utteranceMode
        self.historyEntryID = historyEntryID
        self.historyEntryRevision = historyEntryRevision
        self.aiConversationID = aiConversationID
    }

    public var resolvedUtteranceMode: FlowUtteranceMode {
        utteranceMode ?? .dictation
    }

    /// Instruction deliveries must never insert raw ASR into the field.
    public var allowsRawFallback: Bool {
        resolvedUtteranceMode == .dictation
    }
}

public struct FlowAck: Codable, Equatable, Sendable {
    public enum DeliveryOutcome: String, Codable, Sendable {
        case replaced
        case appended
        case rejected
    }

    public let protocolVersion: Int
    public let sessionId: UUID
    public let utteranceId: UUID
    public let commandSeq: Int64
    public let hostGeneration: String?
    public let revision: Int64?
    public let deliveryOutcome: DeliveryOutcome?
    public let consumedAt: TimeInterval

    public init(
        protocolVersion: Int = 1,
        sessionId: UUID,
        utteranceId: UUID,
        commandSeq: Int64,
        hostGeneration: String? = nil,
        revision: Int64? = nil,
        deliveryOutcome: DeliveryOutcome? = nil,
        consumedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.protocolVersion = protocolVersion
        self.sessionId = sessionId
        self.utteranceId = utteranceId
        self.commandSeq = commandSeq
        self.hostGeneration = hostGeneration
        self.revision = revision
        self.deliveryOutcome = deliveryOutcome
        self.consumedAt = consumedAt
    }
}

public struct FlowStartTransaction: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case issued
        case starting
        case recording
        case terminal
    }

    public let sessionID: UUID
    public let utteranceID: UUID
    public let deadlineAt: TimeInterval
    public let phase: Phase
    public let updatedAt: TimeInterval

    public init(
        sessionID: UUID,
        utteranceID: UUID,
        deadlineAt: TimeInterval,
        phase: Phase,
        updatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.sessionID = sessionID
        self.utteranceID = utteranceID
        self.deadlineAt = deadlineAt
        self.phase = phase
        self.updatedAt = updatedAt
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
        case awaitingDelivery
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
        var journal = decode(
            [FlowCommand].self,
            from: store.data(forKey: FlowSessionKeys.flowCommandJournalPayload)
        ) ?? []
        if !journal.contains(where: { $0.commandSeq == command.commandSeq }) {
            journal.append(command)
            journal.sort { $0.commandSeq < $1.commandSeq }
            journal = Array(journal.suffix(12))
            if let data = encode(journal) {
                store.set(data, forKey: FlowSessionKeys.flowCommandJournalPayload)
            }
        }
        flush(store)
        FlowSessionDarwin.postCommandChanged()
    }

    public static func latestCommand(defaults: UserDefaults? = nil) -> FlowCommand? {
        let store = resolvedDefaults(defaults)
        return decode(FlowCommand.self, from: store.data(forKey: FlowSessionKeys.flowCommandPayload))
    }

    public static func commands(
        after commandSeq: Int64,
        defaults: UserDefaults? = nil
    ) -> [FlowCommand] {
        let store = resolvedDefaults(defaults)
        let journal = decode(
            [FlowCommand].self,
            from: store.data(forKey: FlowSessionKeys.flowCommandJournalPayload)
        ) ?? []
        return journal
            .filter { $0.commandSeq > commandSeq }
            .sorted { $0.commandSeq < $1.commandSeq }
    }

    public static func writeStartTransaction(
        _ transaction: FlowStartTransaction,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        if let data = encode(transaction) {
            store.set(data, forKey: FlowSessionKeys.flowStartTransactionPayload)
        }
        flush(store)
    }

    public static func startTransaction(
        defaults: UserDefaults? = nil
    ) -> FlowStartTransaction? {
        let store = resolvedDefaults(defaults)
        return decode(
            FlowStartTransaction.self,
            from: store.data(forKey: FlowSessionKeys.flowStartTransactionPayload)
        )
    }

    public static func clearStartTransaction(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        flush(store)
    }

    public static func writeResult(_ result: FlowResult, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if let existing = decode(
            FlowResult.self,
            from: store.data(forKey: FlowSessionKeys.flowResultPayload)
        ), existing.sessionId == result.sessionId,
           existing.utteranceId == result.utteranceId,
           isTerminal(existing.status),
           !isTerminal(result.status) {
            return
        }
        if let existing = decode(
            FlowResult.self,
            from: store.data(forKey: FlowSessionKeys.flowResultPayload)
        ), existing.sessionId == result.sessionId,
           existing.utteranceId == result.utteranceId,
           let existingRevision = existing.revision,
           let incomingRevision = result.revision,
           incomingRevision <= existingRevision {
            return
        }
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
        FlowSessionDarwin.postTranscriptionChanged()
    }

    public static func latestAck(defaults: UserDefaults? = nil) -> FlowAck? {
        let store = resolvedDefaults(defaults)
        return decode(FlowAck.self, from: store.data(forKey: FlowSessionKeys.flowAckPayload))
    }

    public static func setPendingKeyboardUtteranceId(
        _ id: UUID?,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        if let id {
            store.set(id.uuidString, forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        } else {
            store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        }
        flush(store)
    }

    public static func pendingKeyboardUtteranceId(defaults: UserDefaults? = nil) -> UUID? {
        let store = resolvedDefaults(defaults)
        guard let raw = store.string(forKey: FlowSessionKeys.pendingKeyboardUtteranceId) else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private static func isTerminal(_ status: FlowResult.Status) -> Bool {
        status == .final || status == .error || status == .aborted || status == .timeout
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
        // PiP sessions are persistent; clear expiry left by older Live Activity builds.
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
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

    /// PiP keep-alive: session stays valid until explicit teardown.
    public static func markSessionActivePersistent(
        sessionId: UUID? = nil,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        let now = Date().timeIntervalSince1970
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.set(now, forKey: FlowSessionKeys.lastActivityAt)
        writeHeartbeat(defaults: store)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.flowCommandPayload)
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        if let sessionId {
            let snapshot = FlowReadySnapshot(
                sessionId: sessionId,
                ready: false,
                reason: .starting,
                heartbeatAt: now,
                engineMode: AppGroupConfiguration.load(fromAvailable: store).engineMode,
                localeId: AppGroupConfiguration.load(fromAvailable: store).localeId,
                sessionExpiresAt: nil,
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
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
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

    /// True when a recent keyboard `startflow` arm should not be repeated.
    public static func isPiPArmInCooldown(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        let last = store.double(forKey: FlowSessionKeys.lastPiPArmAttemptAt)
        guard last > 0 else { return false }
        return Date().timeIntervalSince1970 - last < FlowSessionKeys.pipArmCooldown
    }

    public static func markPiPArmAttempt(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.set(Date().timeIntervalSince1970, forKey: FlowSessionKeys.lastPiPArmAttemptAt)
        flush(store)
    }

    // MARK: - Session validity (keyboard)

    /// True while the persistent PiP session contract is active.
    /// Does **not** mean the host can accept utterances — use `isHostReady()`.
    public static func isSessionActive(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        return store.bool(forKey: FlowSessionKeys.flowSessionActive)
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
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.audioLevels)
        store.removeObject(forKey: FlowSessionKeys.lastActivityAt)
        clearHostReady(defaults: store, notify: false)
        // Previous generation may have died mid Rime/CLM/ASR with hostHeavy=1.
        clearHostHeavy(defaults: store)
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

    /// Host is compiling CLM / deploying Rime / warming ASR — extension must
    /// avoid stacking typing-engine RSS on top.
    public static func setHostHeavy(_ heavy: Bool, defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if heavy {
            store.set(true, forKey: FlowSessionKeys.hostHeavy)
            store.set(Date().timeIntervalSince1970, forKey: FlowSessionKeys.hostHeavyAt)
        } else {
            clearHostHeavy(defaults: store)
        }
        flush(store)
        OSGDiag.log("hostHeavy=\(heavy ? 1 : 0) \(OSGDiag.memoryTag())", category: "flow")
    }

    /// True only while the host recently marked itself busy. A sticky `true`
    /// left by a dead host (no `setHostHeavy(false)`) expires after
    /// `hostHeavyMaxAge` so typing 中文/EN is not silently blocked forever.
    public static func isHostHeavy(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        guard store.bool(forKey: FlowSessionKeys.hostHeavy) else { return false }
        let markedAt = store.double(forKey: FlowSessionKeys.hostHeavyAt)
        // Legacy writes had the bool but no timestamp — treat as stale so a
        // pre-fix sticky flag cannot brick typing after upgrade.
        guard markedAt > 0 else {
            clearHostHeavy(defaults: store)
            flush(store)
            OSGDiag.log("hostHeavy stale missingAt — cleared \(OSGDiag.memoryTag())", category: "flow")
            return false
        }
        let age = Date().timeIntervalSince1970 - markedAt
        guard age >= 0, age <= FlowSessionKeys.hostHeavyMaxAge else {
            clearHostHeavy(defaults: store)
            flush(store)
            OSGDiag.log(
                "hostHeavy stale age=\(Int(age))s — cleared \(OSGDiag.memoryTag())",
                category: "flow"
            )
            return false
        }
        return true
    }

    private static func clearHostHeavy(defaults: UserDefaults) {
        defaults.set(false, forKey: FlowSessionKeys.hostHeavy)
        defaults.removeObject(forKey: FlowSessionKeys.hostHeavyAt)
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
        store.removeObject(forKey: FlowSessionKeys.flowCommandJournalPayload)
        store.removeObject(forKey: FlowSessionKeys.flowResultPayload)
        store.removeObject(forKey: FlowSessionKeys.flowAckPayload)
        store.removeObject(forKey: FlowSessionKeys.flowStartTransactionPayload)
        store.removeObject(forKey: FlowSessionKeys.pendingKeyboardUtteranceId)
        store.removeObject(forKey: FlowSessionKeys.flowReadyPayload)
        clearTranscription(defaults: store)
        store.removeObject(forKey: FlowSessionKeys.audioLevels)
        store.removeObject(forKey: FlowSessionKeys.pendingHostBundleId)
        store.removeObject(forKey: FlowSessionKeys.lastActivityAt)
        clearHostReady(defaults: store, notify: false)
        clearHostHeavy(defaults: store)
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
