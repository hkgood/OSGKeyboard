// FlowSessionBridge+Transcription.swift
// OSGKeyboard · Shared

import Foundation

extension FlowSessionBridge {
    // MARK: - Recording signals (keyboard → host)

    public static func setRecordingState(
        _ state: FlowSessionKeys.RecordingState,
        defaults: UserDefaults? = nil
    ) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(state.rawValue, forKey: FlowSessionKeys.keyboardRecordingState)
        FlowSessionBridgeStorage.flush(store)
    }

    public static func recordingState(
        defaults: UserDefaults? = nil
    ) -> FlowSessionKeys.RecordingState {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        let raw = store.string(forKey: FlowSessionKeys.keyboardRecordingState) ?? FlowSessionKeys.RecordingState.idle.rawValue
        return FlowSessionKeys.RecordingState(rawValue: raw) ?? .idle
    }

    public static func setTranscriptionLanguage(
        _ localeId: String,
        defaults: UserDefaults? = nil
    ) {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(localeId, forKey: FlowSessionKeys.transcriptionLanguage)
        FlowSessionBridgeStorage.flush(store)
    }

    // MARK: - Results (host → keyboard)

    public static func storeTranscriptionResult(
        _ text: String,
        polishWarning: String? = nil,
        defaults: UserDefaults? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(trimmed, forKey: FlowSessionKeys.transcriptionResult)
        store.removeObject(forKey: FlowSessionKeys.transcriptionError)
        store.removeObject(forKey: FlowSessionKeys.transcriptionPartial)
        if let polishWarning, !polishWarning.isEmpty {
            store.set(polishWarning, forKey: FlowSessionKeys.transcriptionPolishWarning)
        } else {
            store.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        }
        setRecordingState(.idle, defaults: store)
        FlowSessionBridgeStorage.flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    /// Host app: publish pipelined ASR partial while recording or finalizing.
    public static func storeTranscriptionPartial(
        _ text: String,
        defaults: UserDefaults? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        if trimmed.isEmpty {
            store.removeObject(forKey: FlowSessionKeys.transcriptionPartial)
        } else {
            store.set(trimmed, forKey: FlowSessionKeys.transcriptionPartial)
        }
        FlowSessionBridgeStorage.flush(store)
        FlowSessionDarwin.postTranscriptionChanged()
    }

    /// Keyboard: read the latest partial without clearing it.
    public static func transcriptionPartial(defaults: UserDefaults? = nil) -> String? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
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
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(message, forKey: FlowSessionKeys.transcriptionError)
        store.set(kind.rawValue, forKey: FlowSessionKeys.transcriptionErrorKind)
        setRecordingState(.idle, defaults: store)
        FlowSessionBridgeStorage.flush(store)
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
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        guard let text = store.string(forKey: FlowSessionKeys.transcriptionResult), !text.isEmpty else {
            return nil
        }
        let warning = store.string(forKey: FlowSessionKeys.transcriptionPolishWarning)
        store.removeObject(forKey: FlowSessionKeys.transcriptionResult)
        store.removeObject(forKey: FlowSessionKeys.transcriptionPolishWarning)
        FlowSessionBridgeStorage.flush(store)
        return TranscriptionDelivery(text: text, polishWarning: warning)
    }

    /// Returns and clears a pending transcription error, if any.
    public static func consumeTranscriptionError(defaults: UserDefaults? = nil) -> FlowTranscriptionError? {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        guard let message = store.string(forKey: FlowSessionKeys.transcriptionError), !message.isEmpty else {
            return nil
        }
        let kindRaw = store.string(forKey: FlowSessionKeys.transcriptionErrorKind)
        let kind = FlowSessionKeys.TranscriptionErrorKind(rawValue: kindRaw ?? "") ?? .generic
        store.removeObject(forKey: FlowSessionKeys.transcriptionError)
        store.removeObject(forKey: FlowSessionKeys.transcriptionErrorKind)
        FlowSessionBridgeStorage.flush(store)
        return FlowTranscriptionError(message: message, kind: kind)
    }

    public static func audioLevels(defaults: UserDefaults? = nil) -> [Float] {
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
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
        let store = FlowSessionBridgeStorage.resolvedDefaults(defaults)
        store.set(levels.map { Double($0) }, forKey: FlowSessionKeys.audioLevels)
        FlowSessionBridgeStorage.flush(store)
    }
}
