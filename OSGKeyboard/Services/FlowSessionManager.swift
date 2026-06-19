// FlowSessionManager.swift
// OSGKeyboard · Main App
//
// Session Owner for TypeWhisper-style Flow dictation: continuous
// `.playAndRecord` capture for the whole session, utterance gating for
// ASR, optional LLM polish, and App Group result delivery.

import Foundation
import AVFoundation
import Speech
import OSGKeyboardShared

@MainActor
final class FlowSessionManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var sessionExpiresAt: Date?
    /// Non-nil when continuous capture failed or permissions are missing.
    @Published private(set) var sessionWarning: String?

    private let capture = FlowContinuousCapture()
    private let asr: ASRService = ASRServiceFactory.make()
    private let polisher = PolishingService()
    private let store = AppGroupStore()

    private var pollingTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var isUtteranceRecording = false
    private var finalizeTask: Task<Void, Never>?
    private var asrTask: Task<Void, Never>?
    private var currentPartial = ""
    private var lastFinal = ""

    init() {
        Task { @MainActor [weak self] in
            await self?.bootstrapFromStorageIfNeeded()
        }
    }

    // MARK: - Public

    /// Starts a Flow session: permissions → continuous capture → App Group active.
    func startSession(duration: TimeInterval = FlowSessionKeys.defaultSessionDuration) {
        guard AppGroup.isAvailable else {
            debug("cannot start flow session: App Group unavailable")
            return
        }

        if isActive {
            extendSession(duration: duration)
            return
        }

        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            await self?.startSessionAsync(duration: duration)
        }
    }

    /// Called on launch / foreground when onboarding is complete.
    func autoStartIfNeeded() {
        guard AppGroup.isAvailable else { return }
        guard !isActive, !isStarting else { return }

        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            return
        }

        let markedActive = AppGroup.defaults.bool(forKey: FlowSessionKeys.flowSessionActive)
        if markedActive, FlowSessionBridge.remainingSessionDuration() != nil {
            Task { await bootstrapFromStorageIfNeeded() }
            return
        }

        startSession()
    }

    /// Reattach capture when the host app was killed but the session has not expired.
    func bootstrapFromStorageIfNeeded() async {
        guard AppGroup.isAvailable, !isActive else { return }

        let markedActive = AppGroup.defaults.bool(forKey: FlowSessionKeys.flowSessionActive)
        guard markedActive, let remaining = FlowSessionBridge.remainingSessionDuration(), remaining > 0 else {
            if markedActive {
                FlowSessionBridge.markSessionInactive()
            }
            return
        }

        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            return
        }

        isStarting = true
        sessionWarning = nil
        defer { isStarting = false }

        do {
            try capture.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionWarning = message
            FlowSessionBridge.markSessionInactive()
            debug("bootstrap capture failed: \(message)")
            return
        }

        FlowSessionBridge.writeHeartbeat()
        FlowSessionDarwin.postSessionChanged()
        isActive = true
        if let expires = FlowSessionBridge.sessionExpiresAt() {
            sessionExpiresAt = Date(timeIntervalSince1970: expires)
        }

        startHeartbeat()
        startPolling()
        startLevelPublishing()
        scheduleExpiry(after: remaining)

        debug("Flow session restored (\(Int(remaining))s remaining)")
    }

    func endSession() {
        guard isActive else { return }
        debug("Flow session ended")

        startTask?.cancel()
        startTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        levelTask?.cancel()
        levelTask = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        asrTask?.cancel()
        asrTask = nil

        if isUtteranceRecording {
            capture.cancelUtterance()
            asr.cancel()
            isUtteranceRecording = false
        }

        capture.stop()
        FlowSessionBridge.markSessionInactive()
        FlowSessionDarwin.postSessionChanged()
        isActive = false
        sessionExpiresAt = nil
        sessionWarning = nil
        currentPartial = ""
        lastFinal = ""
    }

    func extendSession(duration: TimeInterval = FlowSessionKeys.defaultSessionDuration) {
        FlowSessionBridge.extendSession(by: duration)
        sessionExpiresAt = Date().addingTimeInterval(duration)
        scheduleExpiry(after: duration)
    }

    // MARK: - Session start

    private func startSessionAsync(duration: TimeInterval) async {
        isStarting = true
        sessionWarning = nil
        defer { isStarting = false }

        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            return
        }

        do {
            try capture.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionWarning = message
            debug("continuous capture failed: \(message)")
            return
        }

        FlowSessionBridge.markSessionActive(duration: duration)
        FlowSessionDarwin.postSessionChanged()
        isActive = true
        sessionExpiresAt = Date().addingTimeInterval(duration)

        startHeartbeat()
        startPolling()
        startLevelPublishing()
        scheduleExpiry(after: duration)

        debug("Flow session started (\(Int(duration))s), continuous capture running")
    }

    private func permissionWarningMessage() -> String {
        if AppPermissions.micStatus != .granted {
            return NSLocalizedString("flow.error.micRequired", comment: "")
        }
        return NSLocalizedString("flow.error.speechRequired", comment: "")
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.handleKeyboardSignal()
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func handleKeyboardSignal() {
        switch FlowSessionBridge.recordingState() {
        case .recording:
            guard !isUtteranceRecording else { return }
            beginUtterance()
        case .stopped:
            guard isUtteranceRecording else { return }
            endUtterance()
        case .aborted:
            abortUtterance()
        case .idle, .processing:
            break
        }
    }

    private func beginUtterance() {
        guard capture.running else {
            failUtterance(message: NSLocalizedString("flow.error.audioUnavailable", comment: ""))
            return
        }

        finalizeTask?.cancel()
        asrTask?.cancel()
        asr.cancel()
        currentPartial = ""
        lastFinal = ""

        let localeId = store.localeId
        FlowSessionBridge.setTranscriptionLanguage(localeId)
        FlowSessionBridge.clearPendingTranscription()

        let locale = SpeechLocaleResolver.resolve(localeId)
        let stream = capture.beginUtterance()
        let events = asr.transcribe(stream: stream, locale: locale)

        isUtteranceRecording = true

        asrTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await event in events {
                switch event {
                case .capability:
                    break
                case .partial(let text):
                    self.currentPartial = text
                case .final(let text):
                    self.lastFinal = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.currentPartial = ""
                case .error(let message):
                    self.debug("asr error: \(message)")
                    if self.isUtteranceRecording {
                        self.failUtterance(message: message)
                    }
                }
            }
        }

        debug("utterance recording started")
    }

    private func endUtterance() {
        isUtteranceRecording = false
        capture.endUtterance()
        FlowSessionBridge.setRecordingState(.processing)

        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            await self?.finalizeUtterance()
        }
        debug("utterance stopped, finalizing")
    }

    private func abortUtterance() {
        isUtteranceRecording = false
        finalizeTask?.cancel()
        asrTask?.cancel()
        asr.cancel()
        capture.cancelUtterance()
        currentPartial = ""
        lastFinal = ""
        FlowSessionBridge.setRecordingState(.idle)
        debug("utterance aborted")
    }

    private func failUtterance(message: String) {
        isUtteranceRecording = false
        asrTask?.cancel()
        asr.cancel()
        capture.cancelUtterance()
        currentPartial = ""
        lastFinal = ""
        FlowSessionBridge.storeTranscriptionError(message)
        debug("utterance failed: \(message)")
    }

    private func finalizeUtterance() async {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if !lastFinal.isEmpty { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        var text = lastFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else {
            FlowSessionBridge.storeTranscriptionError(
                NSLocalizedString("flow.error.noSpeech", comment: "")
            )
            return
        }

        let engineMode = store.engineMode
        let modeId = store.modeId
        let shouldPolish = engineMode != "local" && modeId == "polish"

        if shouldPolish {
            do {
                let polished = try await polisher.polish(text)
                FlowSessionBridge.storeTranscriptionResult(polished)
            } catch {
                FlowSessionBridge.storeTranscriptionResult(text)
            }
        } else {
            FlowSessionBridge.storeTranscriptionResult(text)
        }

        currentPartial = ""
        lastFinal = ""
        debug("utterance finalized length=\(text.count)")
    }

    // MARK: - Level publishing (main thread only)

    private func startLevelPublishing() {
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive else { break }
                let levels = self.capture.currentAudioLevels()
                if levels.contains(where: { $0 > 0 }) {
                    FlowSessionBridge.storeAudioLevels(levels)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    // MARK: - Timers

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        FlowSessionBridge.writeHeartbeat()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                FlowSessionBridge.writeHeartbeat()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self?.isActive == true else { break }
            }
        }
    }

    private func scheduleExpiry(after duration: TimeInterval) {
        expiryTask?.cancel()
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.endSession()
        }
    }

    private func debug(_ message: String) {
        #if DEBUG
        print("🌊[FlowSession] \(message)")
        #endif
    }
}
