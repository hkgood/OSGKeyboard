// FlowSessionBridge.swift
// OSGKeyboard · Shared
//
// TypeWhisper-style Flow session bridge: keyboard writes recording
// signals; host app writes transcription results. Legacy one-shot
// dictation handoff remains in `DictationBridge`.

import Foundation

public enum FlowSessionBridge {
    private static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults { return defaults }
        return AppGroup.isAvailable ? AppGroup.defaults : .standard
    }

    /// Force cross-process visibility. Must only be called on the main thread.
    private static func flush(_ store: UserDefaults) {
        if Thread.isMainThread {
            store.synchronize()
        }
    }

    // MARK: - Session lifecycle (host app)

    public static func markSessionActive(
        duration: TimeInterval = FlowSessionKeys.defaultSessionDuration,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        let expires = Date().timeIntervalSince1970 + duration
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        store.set(expires, forKey: FlowSessionKeys.flowSessionExpires)
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
        flush(store)
    }

    public static func writeHeartbeat(defaults: UserDefaults? = nil) {
        let store = resolvedDefaults(defaults)
        store.set(Date().timeIntervalSince1970, forKey: FlowSessionKeys.flowHeartbeat)
        flush(store)
    }

    public static func extendSession(
        by duration: TimeInterval = FlowSessionKeys.defaultSessionDuration,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        let expires = Date().timeIntervalSince1970 + duration
        store.set(true, forKey: FlowSessionKeys.flowSessionActive)
        store.set(expires, forKey: FlowSessionKeys.flowSessionExpires)
        flush(store)
    }

    // MARK: - Session validity (keyboard)

    /// True when the session contract is still valid (not expired).
    /// Does not require a fresh heartbeat — the host may be suspended in
    /// background while the continuous audio session is frozen.
    public static func isSessionActive(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        flush(store)
        guard store.bool(forKey: FlowSessionKeys.flowSessionActive) else { return false }

        let expires = store.double(forKey: FlowSessionKeys.flowSessionExpires)
        return expires > Date().timeIntervalSince1970
    }

    /// True when the host app recently wrote a heartbeat (foreground or
    /// actively processing). Used for auto-start heuristics, not gating record.
    public static func isHostReachable(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        flush(store)
        guard isSessionActive(defaults: store) else { return false }

        let heartbeat = store.double(forKey: FlowSessionKeys.flowHeartbeat)
        guard heartbeat > 0 else { return false }

        let staleness = Date().timeIntervalSince1970 - heartbeat
        return staleness <= FlowSessionKeys.heartbeatStaleInterval
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
        if let polishWarning, !polishWarning.isEmpty {
            store.set(polishWarning, forKey: FlowSessionKeys.transcriptionPolishWarning)
        } else {
            store.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        }
        setRecordingState(.idle, defaults: store)
        flush(store)
    }

    public static func storeTranscriptionError(
        _ message: String,
        defaults: UserDefaults? = nil
    ) {
        let store = resolvedDefaults(defaults)
        store.set(message, forKey: FlowSessionKeys.transcriptionError)
        setRecordingState(.idle, defaults: store)
        flush(store)
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
        flush(store)
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
    public static func consumeTranscriptionError(defaults: UserDefaults? = nil) -> String? {
        let store = resolvedDefaults(defaults)
        flush(store)
        guard let message = store.string(forKey: FlowSessionKeys.transcriptionError), !message.isEmpty else {
            return nil
        }
        store.removeObject(forKey: FlowSessionKeys.transcriptionError)
        flush(store)
        return message
    }

    public static func audioLevels(defaults: UserDefaults? = nil) -> [Float] {
        let store = resolvedDefaults(defaults)
        flush(store)
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
        flush(store)
    }

    private static func clearTranscription(defaults: UserDefaults) {
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionResult)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        defaults.removeObject(forKey: FlowSessionKeys.transcriptionError)
    }
}
