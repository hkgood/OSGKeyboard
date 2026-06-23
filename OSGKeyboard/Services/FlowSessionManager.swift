// FlowSessionManager.swift
// OSGKeyboard · Main App
//
// Session Owner for TypeWhisper-style Flow dictation: continuous
// `.playAndRecord` capture for the whole session, utterance gating for
// ASR and cloud LLM polish, with App Group result delivery.

import Foundation
import AVFoundation
import Speech
import OSGKeyboardShared
import UIKit
import SwiftUI

@MainActor
final class FlowSessionManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var sessionExpiresAt: Date?
    /// Non-nil when continuous capture failed or permissions are missing.
    @Published private(set) var sessionWarning: String?

    private let capture = FlowContinuousCapture()
    private let store = AppGroupStore()
    /// Cloud-engine polish; local engine now ALSO runs through the
    /// polisher when `localModeCloudPolishEnabled` is on — the same
    /// `PolishingService` short-circuits to raw when the toggle is off.
    private var polisher: PolishingService {
        PolishingService()
    }
    /// Cached ASR instance. v0.2.0: the only on-device backend is iOS
    /// `SpeechAnalyzer`, which has no warm-up step — we can hand the
    /// factory-built service straight back without going through the
    /// old `OnDeviceModelWarmup` registry.
    private var sessionASR: ASRService?
    private var asr: ASRService {
        if let sessionASR { return sessionASR }
        let service = ASRServiceFactory.make(
            engineMode: store.engineMode,
            localBackend: store.localASRBackend
        )
        sessionASR = service
        return service
    }

    private var pollingTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var isUtteranceRecording = false
    /// True from `stopped` until the result/error is written back to App Group.
    private var isUtteranceProcessing = false
    private var finalizeTask: Task<Void, Never>?
    private var asrTask: Task<Void, Never>?
    private var chunkedPipeline: ChunkedUtterancePipeline?
    private var currentPartial = ""
    private var lastFinal = ""
    private var chunkWarnings: [String] = []
    /// True while the host app scene is `.active` — drives foreground renewal.
    private var isAppForeground = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

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

        // v0.2.0: iOS `SpeechAnalyzer` needs no warm-up. We still
        // re-bind the cached `sessionASR` so a config flip mid-session
        // (e.g. switching from cloud to local) is honoured.
        bindSessionASR()

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

        if isUtteranceRecording || isUtteranceProcessing {
            capture.cancelUtterance()
            asrTask?.cancel()
            Task { await chunkedPipeline?.cancel() }
            asr.cancel()
        }
        asrTask = nil
        chunkedPipeline = nil
        isUtteranceRecording = false
        isUtteranceProcessing = false

        capture.stop()
        endBackgroundKeepAlive()
        sessionASR = nil
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

    /// Called from `OSGKeyboardApp` when `scenePhase` changes.
    func setAppForeground(_ foreground: Bool) {
        isAppForeground = foreground
        if foreground, isActive {
            renewSessionIfNeededWhileForeground()
        }
    }

    /// Full scene lifecycle — keeps Flow + ASR alive across app switches.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            FlowAppLifecycle.shared.setForeground(true)
            setAppForeground(true)
            resumeAfterForeground()
        case .inactive:
            writeHeartbeatIfActive()
        case .background:
            FlowAppLifecycle.shared.setForeground(false)
            setAppForeground(false)
            beginBackgroundKeepAlive()
        @unknown default:
            break
        }
    }

    private func writeHeartbeatIfActive() {
        guard isActive else { return }
        FlowSessionBridge.writeHeartbeat()
    }

    private func beginBackgroundKeepAlive() {
        guard isActive else { return }
        FlowSessionBridge.writeHeartbeat()

        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundKeepAlive()
        }
        debug("background keep-alive started")
    }

    private func endBackgroundKeepAlive() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        debug("background keep-alive ended")
    }

    private func resumeAfterForeground() {
        guard isActive else {
            endBackgroundKeepAlive()
            return
        }

        FlowSessionBridge.writeHeartbeat()
        endBackgroundKeepAlive()

        Task { @MainActor [weak self] in
            await self?.reactivateCaptureIfNeeded()
            // v0.2.0: iOS `SpeechAnalyzer` is bundled with the OS; no
            // on-device weights to reload after a background trip.
            self?.bindSessionASR()
        }
    }

    private func reactivateCaptureIfNeeded() async {
        guard isActive else { return }

        if capture.running {
            capture.reassertIfRunning()
            return
        }

        do {
            try capture.start()
            debug("capture restarted after foreground")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionWarning = message
            debug("capture restart failed: \(message)")
        }
    }

    /// Extend the session before it expires while the host app stays in foreground.
    private func renewSessionIfNeededWhileForeground() {
        guard isActive, isAppForeground else { return }
        guard let remaining = FlowSessionBridge.remainingSessionDuration() else { return }
        let threshold = FlowSessionKeys.defaultSessionDuration * 0.25
        guard remaining < threshold else { return }
        extendSession()
        debug("Flow session renewed in foreground (\(Int(threshold))s threshold)")
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

        // v0.2.0: iOS `SpeechAnalyzer` needs no warm-up; just refresh
        // the cached ASR service in case the user flipped engines
        // while the session was idle.
        bindSessionASR()

        debug("Flow session started (\(Int(duration))s), continuous capture running")
    }

    private func bindSessionASR() {
        sessionASR = ASRServiceFactory.make(
            engineMode: store.engineMode,
            localBackend: store.localASRBackend
        )
    }

    private func permissionWarningMessage() -> String {
        if AppPermissions.micStatus != .granted {
            return AppL10n.string("flow.error.micRequired")
        }
        return AppL10n.string("flow.error.speechRequired")
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.handleKeyboardSignal()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func handleKeyboardSignal() {
        switch FlowSessionBridge.recordingState() {
        case .recording:
            guard !isUtteranceRecording, !isUtteranceProcessing else { return }
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
            failUtterance(message: AppL10n.string("flow.error.audioUnavailable"))
            return
        }
        guard !isUtteranceProcessing else {
            debug("beginUtterance ignored — previous utterance still processing")
            return
        }

        // Honor engine / ASR backend changes without restarting the session.
        bindSessionASR()

        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []

        let localeId = store.localeId
        FlowSessionBridge.setTranscriptionLanguage(localeId)
        FlowSessionBridge.clearPendingTranscription()

        let locale = SpeechLocaleResolver.resolve(localeId)
        let stream = capture.beginUtterance()
        let pipeline = ChunkedUtterancePipeline(asr: asr, locale: locale)
        chunkedPipeline = pipeline

        isUtteranceRecording = true
        FlowDiagnostics.log(
            "beginUtterance engine=\(store.engineMode) asr=\(store.localASRBackend.rawValue) " +
            "asrType=\(type(of: asr)) pipelined=true max=\(Int(FlowSessionKeys.maxUtteranceDuration))s"
        )

        asrTask = Task.detached(priority: .userInitiated) { [weak manager = self] in
            let outcome = await pipeline.transcribe(stream: stream) { partial in
                Task { @MainActor in
                    manager?.currentPartial = partial
                }
            }
            // Re-bind `manager` inside the `@MainActor` block so the
            // weak reference is captured under the right isolation. Swift
            // 6 strict concurrency otherwise complains about a
            // task-isolated reference escaping into a main-actor closure.
            await MainActor.run { [weak manager] in
                guard let manager else { return }
                FlowDiagnostics.log(
                    "chunkedASR finished partialLen=\(manager.currentPartial.count) " +
                    "finalPending=\(manager.lastFinal.isEmpty)"
                )
                switch outcome {
                case .success(let success):
                    manager.lastFinal = success.text
                    manager.chunkWarnings = success.chunkWarnings
                    manager.currentPartial = ""
                case .failure(let message):
                    manager.debug("asr error: \(message)")
                    if manager.isUtteranceRecording {
                        manager.failUtterance(message: message)
                    } else if manager.isUtteranceProcessing {
                        manager.finishProcessing(withError: message)
                    }
                case .cancelled:
                    break
                }
            }
        }

        debug("utterance recording started")
    }

    private func endUtterance() {
        guard isUtteranceRecording else { return }

        // Close the mic gate first, then mark processing before dropping the
        // recording flag so the poll loop cannot start a second utterance.
        capture.endUtterance()
        FlowSessionBridge.setRecordingState(.processing)
        isUtteranceRecording = false
        isUtteranceProcessing = true

        // Do NOT cancel `asrTask` or `asr` — the preview pipeline relies on
        // the consumer staying alive until `.final` lands (see
        // `PreviewASRControllerStateTests`).

        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            await self?.finalizeUtterance()
        }
        debug("utterance stopped, finalizing")
    }

    private func abortUtterance() {
        isUtteranceRecording = false
        isUtteranceProcessing = false
        finalizeTask?.cancel()
        finalizeTask = nil
        asrTask?.cancel()
        Task { await chunkedPipeline?.cancel() }
        chunkedPipeline = nil
        asr.cancel()
        capture.cancelUtterance()
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        FlowSessionBridge.setRecordingState(.idle)
        debug("utterance aborted")
    }

    private func failUtterance(message: String) {
        isUtteranceRecording = false
        isUtteranceProcessing = false
        finalizeTask?.cancel()
        finalizeTask = nil
        asrTask?.cancel()
        Task { await chunkedPipeline?.cancel() }
        chunkedPipeline = nil
        asr.cancel()
        capture.cancelUtterance()
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        FlowSessionBridge.storeTranscriptionError(message)
        FlowSessionBridge.setRecordingState(.idle)
        debug("utterance failed: \(message)")
    }

    private func finishProcessing(withError message: String) {
        isUtteranceProcessing = false
        finalizeTask?.cancel()
        finalizeTask = nil
        chunkedPipeline = nil
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        FlowSessionBridge.storeTranscriptionError(message)
        FlowSessionBridge.setRecordingState(.idle)
        debug("utterance processing failed: \(message)")
    }

    private func finalizeUtterance() async {
        let pipelineStarted = Date()
        defer {
            isUtteranceProcessing = false
            FlowSessionBridge.setRecordingState(.idle)
        }

        let asrWait = asrWaitTimeout()
        FlowDiagnostics.log(
            "finalize start asrWait=\(Int(asrWait))s engine=\(store.engineMode) " +
            "backend=\(store.localASRBackend.rawValue)"
        )

        let asrDeadline = Date().addingTimeInterval(asrWait)
        while Date() < asrDeadline {
            if !lastFinal.isEmpty { break }
            if asrTask?.isCancelled == true { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if lastFinal.isEmpty, let asrTask {
            FlowDiagnostics.log("ASR wait elapsed — awaiting asrTask completion")
            _ = await asrTask.value
        }

        let asrElapsed = Date().timeIntervalSince(pipelineStarted)
        FlowDiagnostics.log("ASR phase done in \(String(format: "%.1f", asrElapsed))s finalLen=\(lastFinal.count)")

        var text = lastFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else {
            let key = (asrTask?.isCancelled == true)
                ? "flow.error.recognitionInterrupted"
                : "flow.error.noSpeech"
            FlowDiagnostics.log("finalize failed: empty transcript after \(String(format: "%.1f", asrElapsed))s")
            FlowSessionBridge.storeTranscriptionError(
                AppL10n.string(key)
            )
            return
        }

        let engineMode = store.engineMode
        let chunkNote = Self.chunkWarningMessage(chunkWarnings)
        let shouldPolish = (engineMode == "cloud")
            || (engineMode == "local" && store.localModeCloudPolishEnabled)

        if !shouldPolish {
            // Local engine, cloud-polish toggle off — pure ASR.
            FlowSessionBridge.storeTranscriptionResult(text, polishWarning: chunkNote)
            FlowDiagnostics.log(
                "finalize ASR-only total=\(String(format: "%.1f", Date().timeIntervalSince(pipelineStarted)))s " +
                "len=\(text.count)"
            )
            SpeechHistoryStore.shared.append(text: text, engineMode: engineMode)
            currentPartial = ""
            lastFinal = ""
            chunkWarnings = []
            debug("utterance finalized length=\(text.count)")
            return
        }

        var delivered = text
        let polishStarted = Date()
        do {
            let polished = try await polisher.polish(text)
            delivered = polished
            FlowSessionBridge.storeTranscriptionResult(polished, polishWarning: chunkNote)
            FlowDiagnostics.log(
                "polish done in \(String(format: "%.1f", Date().timeIntervalSince(polishStarted)))s " +
                "total=\(String(format: "%.1f", Date().timeIntervalSince(pipelineStarted)))s"
            )
        } catch {
            // v0.2.0: local + cloud-polish-on + no API key surfaces
            // `.missingAPIKey`. We translate it into a polishWarning
            // so the keyboard can show the "fill in your key" hint
            // inline rather than a generic failure message. The raw
            // transcript is still delivered — no data loss.
            let warning = Self.warningFromPolishError(error) ?? chunkNote
            FlowDiagnostics.log(
                "polish failed after \(String(format: "%.1f", Date().timeIntervalSince(polishStarted)))s: " +
                "\(error.localizedDescription)"
            )
            FlowSessionBridge.storeTranscriptionResult(text, polishWarning: warning)
        }

        SpeechHistoryStore.shared.append(text: delivered, engineMode: engineMode)

        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        chunkedPipeline = nil
        debug("utterance finalized length=\(text.count)")
    }

    private static func chunkWarningMessage(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.joined(separator: "\n")
    }

    /// v0.2.0: surface the local-mode cloud-polish error path with a
    /// localised hint ("please fill in your DeepSeek key in Settings")
    /// rather than letting the keyboard show a generic network error.
    private static func warningFromPolishError(_ error: Error) -> String? {
        guard let polishError = error as? PolishingService.PolishError,
              polishError == .missingAPIKey else {
            return nil
        }
        return AppL10n.string("flow.warning.cloudPolishMissingKey")
    }

    private func asrWaitTimeout() -> TimeInterval {
        // v0.2.0: local engine is iOS `SpeechAnalyzer` only, so the
        // previous Qwen3-specific timeout collapses into the shared
        // local path.
        if store.engineMode == "local" {
            return FlowSessionKeys.localASRWaitTimeout
        }
        return FlowSessionKeys.cloudASRWaitTimeout
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
                self?.renewSessionIfNeededWhileForeground()
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
        FlowDiagnostics.log(message)
    }
}
