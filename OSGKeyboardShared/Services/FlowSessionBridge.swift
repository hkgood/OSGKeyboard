// FlowSessionBridge.swift
// OSGKeyboard · Shared
//
// TypeWhisper-style Flow session bridge: keyboard writes recording
// signals; host app writes transcription results.

import Foundation

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

    /// Keyboard/read side: refresh App Group defaults after the extension was
    /// suspended so decisions are not based on stale in-process caches.
    public static func reloadFromDisk(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        if Thread.isMainThread {
            store.synchronize()
        }
    }

    // MARK: - Session lifecycle (host app)

    public static func markSessionActive(
        duration: TimeInterval? = nil,
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
        setRecordingState(.idle, defaults: store)
        clearTranscription(defaults: store)
        flush(store)
    }

    public static func markSessionInactive(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.set(false, forKey: FlowSessionKeys.flowSessionActive)
        store.removeObject(forKey: FlowSessionKeys.flowSessionExpires)
        store.removeObject(forKey: FlowSessionKeys.flowHeartbeat)
        setRecordingState(.idle, defaults: store)
        clearTranscription(defaults: store)
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
