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
    /// Cold-start handoff overlay state (scheme B).
    @Published var coldStartContext: FlowColdStartContext?

    private let capture = FlowContinuousCapture()
    private let store = AppGroupStore()
    /// Cloud-engine polish; local engine runs through built-in DeepSeek polish.
    private var polisher: PolishingService {
        PolishingService()
    }
    /// Cached ASR instance. v0.2.0: the only on-device backend is iOS
    /// `SpeechAnalyzer`, which has no warm-up step — we can hand the
    /// factory-built service straight back without going through the
    /// old `OnDeviceModelWarmup` registry.
    private var sessionASR: ASRService?
    /// Tracks which engine mode `sessionASR` was created for.
    private var sessionASREngineMode: String?
    /// Locale id last passed to `warmup(locale:)`.
    private var sessionASRWarmedLocaleID: String?
    private var asr: ASRService {
        if let sessionASR { return sessionASR }
        let service = ASRServiceFactory.make(store: store)
        sessionASR = service
        return service
    }

    private var pollingTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    /// Last recording state the poll loop observed — logs only on transition.
    private var lastObservedRecordingState: FlowSessionKeys.RecordingState = .idle
    private var isUtteranceRecording = false
    /// True from `stopped` until the result/error is written back to App Group.
    private var isUtteranceProcessing = false
    private var finalizeTask: Task<Void, Never>?
    private var asrTask: Task<Void, Never>?
    private var chunkedPipeline: ChunkedUtterancePipeline?
    private var currentPartial = ""
    private var lastFinal = ""
    private var chunkWarnings: [String] = []
    /// Wall-clock span of the current mic-open utterance (excludes LLM polish).
    private var utteranceRecordingStartedAt: Date?
    /// True while the host app scene is `.active` — drives foreground renewal.
    private var isAppForeground = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// True while handling a keyboard-initiated `startflow` cold start.
    private var isColdStartHandoff = false

    init() {
        // Sessions are (re)started explicitly on app foreground via
        // `activateOnForeground()`. We deliberately do NOT silently reattach a
        // stored session here — after a force-quit that would resurrect capture
        // (and keep a stale Live Activity alive) without the user re-opening.
    }

    // MARK: - Public

    /// Starts a Flow session: permissions → continuous capture → App Group active.
    func startSession(duration: TimeInterval? = nil, coldStart: Bool = false) {
        guard AppGroup.isAvailable else {
            debug("cannot start flow session: App Group unavailable")
            return
        }

        if coldStart {
            isColdStartHandoff = true
        }

        reconcilePersistedFlowStateBeforeStart()

        if isActive {
            extendSession(duration: duration)
            if coldStart {
                Task { @MainActor [weak self] in
                    self?.handleColdStartAfterSessionReady()
                }
            }
            return
        }

        guard !isStarting else { return }

        startTask?.cancel()
        startTask = Task { @MainActor [weak self] in
            await self?.startSessionAsync(duration: duration)
            self?.handleColdStartAfterSessionReady()
        }
    }

    /// Clears App Group Flow state left behind when the host process was killed
    /// or the device rebooted while the session flag was still set.
    private func reconcilePersistedFlowStateBeforeStart() {
        if FlowSessionBridge.isHostStale() {
            if isActive {
                endSession()
            } else {
                FlowSessionBridge.clearFlowState()
                FlowLiveActivityController.endSession()
            }
            debug("reconciled zombie persisted Flow state")
            return
        }

        guard !isActive else { return }

        let orphaned = FlowSessionBridge.recordingState()
        switch orphaned {
        case .recording, .stopped, .processing:
            FlowSessionBridge.setRecordingState(.idle)
            FlowSessionBridge.clearPendingTranscription()
            debug("cleared orphaned keyboard recording state: \(orphaned.rawValue)")
        case .idle, .aborted:
            break
        }
    }

    /// Auto-start (or renew) the Flow session on every app foreground when
    /// permissions allow — the "always auto-open, no off switch" policy. Also
    /// clears any orphaned Live Activity a previously force-quit process left
    /// behind (its `endSession()` could not run at kill time).
    func activateOnForeground() {
        guard AppGroup.isAvailable else { return }
        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            FlowLiveActivityController.endSession()
            return
        }
        startSession()
    }

    func dismissColdStartOverlay() {
        coldStartContext = nil
        isColdStartHandoff = false
    }

    func returnToPendingHostFromColdStart() {
        _ = HostReturnService.openPendingHostIfPossible()
        dismissColdStartOverlay()
    }

    func endSession() {
        guard isActive else { return }
        debug("Flow session ended")

        dismissColdStartOverlay()
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
        ScreenWakeLock.release()
        sessionASR = nil
        sessionASREngineMode = nil
        sessionASRWarmedLocaleID = nil
        FlowSessionBridge.markSessionInactive()
        FlowSessionDarwin.postSessionChanged()
        FlowLiveActivityController.endSession()
        isActive = false
        sessionExpiresAt = nil
        sessionWarning = nil
        currentPartial = ""
        lastFinal = ""
    }

    func extendSession(duration: TimeInterval? = nil) {
        let resolved = duration ?? FlowSessionPolicy.sessionDuration()
        FlowSessionBridge.extendSession(by: resolved)
        sessionExpiresAt = Date().addingTimeInterval(resolved)
        scheduleExpiry(after: resolved)
    }

    /// Called from `OSGKeyboardApp` when `scenePhase` changes.
    func setAppForeground(_ foreground: Bool) {
        isAppForeground = foreground
    }

    /// Full scene lifecycle — keeps Flow + ASR alive across app switches.
    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            setAppForeground(true)
            resumeAfterForeground()
        case .inactive:
            writeHeartbeatIfActive()
        case .background:
            setAppForeground(false)
            if coldStartContext != nil {
                dismissColdStartOverlay()
            }
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
            self?.bindSessionASRIfNeeded()
            self?.scheduleASRWarmup()
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

    /// Extend expiry after utterance completion based on the inactivity policy.
    private func touchSessionActivity() {
        guard isActive else { return }
        FlowSessionBridge.touchLastActivity()
        if let expires = FlowSessionBridge.sessionExpiresAt() {
            sessionExpiresAt = Date(timeIntervalSince1970: expires)
            let remaining = expires - Date().timeIntervalSince1970
            if remaining > 0 {
                scheduleExpiry(after: remaining)
            }
        }
    }

    // MARK: - Session start

    private func startSessionAsync(duration: TimeInterval?) async {
        isStarting = true
        sessionWarning = nil
        defer { isStarting = false }

        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            isColdStartHandoff = false
            return
        }

        do {
            try capture.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionWarning = message
            isColdStartHandoff = false
            debug("continuous capture failed: \(message)")
            return
        }

        let resolvedDuration = duration ?? FlowSessionPolicy.sessionDuration()
        FlowSessionBridge.markSessionActive(duration: resolvedDuration)
        FlowSessionDarwin.postSessionChanged()
        isActive = true
        ScreenWakeLock.acquire()
        sessionExpiresAt = Date().addingTimeInterval(resolvedDuration)

        startHeartbeat()
        startPolling()
        startLevelPublishing()
        scheduleExpiry(after: resolvedDuration)

        bindSessionASRIfNeeded()
        scheduleASRWarmup()
        FlowLiveActivityController.startSession()

        debug("Flow session started (\(Int(resolvedDuration))s inactivity window), continuous capture running")
    }

    @MainActor
    private func handleColdStartAfterSessionReady() {
        guard isColdStartHandoff, isActive else { return }

        let hostEntry = HostReturnService.pendingHostEntry()
        let skipSwitch = FlowSessionPolicy.skipAppSwitch()

        if skipSwitch, hostEntry != nil, HostReturnService.openPendingHostIfPossible() {
            dismissColdStartOverlay()
            return
        }

        coldStartContext = FlowColdStartContext(hostEntry: hostEntry)
    }

    private func bindSessionASRIfNeeded(force: Bool = false) {
        let engineMode = store.engineMode
        if !force,
           sessionASR != nil,
           sessionASREngineMode == engineMode {
            return
        }
        sessionASR?.cancel()
        sessionASR = ASRServiceFactory.make(store: store)
        sessionASREngineMode = engineMode
        sessionASRWarmedLocaleID = nil
    }

    private func scheduleASRWarmup() {
        Task { @MainActor [weak self] in
            await self?.warmupASRIfNeeded()
        }
    }

    private func warmupASRIfNeeded() async {
        bindSessionASRIfNeeded()
        let locale = SpeechLocaleResolver.resolve(store.localeId)
        let localeID = locale.identifier(.bcp47)
        guard sessionASRWarmedLocaleID != localeID else { return }
        await asr.warmup(locale: locale)
        sessionASRWarmedLocaleID = localeID
        FlowDiagnostics.log("ASR warmup complete locale=\(localeID)")
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
        lastObservedRecordingState = FlowSessionBridge.recordingState()
        FlowDiagnostics.log(
            "polling started: initialRecordingState=\(lastObservedRecordingState.rawValue) " +
            "container=\(AppGroup.containerPathForDiagnostics)"
        )
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.handleKeyboardSignal()
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func handleKeyboardSignal() {
        let signal = FlowSessionBridge.recordingState()
        if signal != lastObservedRecordingState {
            // The single most important cross-process signal: proves whether the
            // host actually SEES the keyboard's recording state writes.
            FlowDiagnostics.log(
                "poll observed recordingState \(lastObservedRecordingState.rawValue) → \(signal.rawValue) " +
                "[rec=\(isUtteranceRecording) proc=\(isUtteranceProcessing) fg=\(isAppForeground)]"
            )
            lastObservedRecordingState = signal
        }
        switch signal {
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
            failUtterance(
                message: AppL10n.string("flow.error.audioUnavailable"),
                kind: .audioUnavailable
            )
            return
        }
        guard !isUtteranceProcessing else {
            debug("beginUtterance ignored — previous utterance still processing")
            return
        }

        // Usually already warm from session start; refresh without blocking the mic gate.
        scheduleASRWarmup()

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
        utteranceRecordingStartedAt = Date()
        FlowLiveActivityController.update(phase: .recording)
        FlowDiagnostics.log(
            "beginUtterance engine=\(store.engineMode) " +
            "asrType=\(type(of: asr)) pipelined=true " +
            "localCustomLM=\(store.localASRCustomLanguageModelEnabled) " +
            "max=\(Int(FlowSessionKeys.maxUtteranceDuration))s"
        )

        asrTask = Task.detached(priority: .userInitiated) { [weak manager = self] in
            let outcome = await pipeline.transcribe(stream: stream) { partial in
                Task { @MainActor in
                    manager?.currentPartial = partial
                    FlowSessionBridge.storeTranscriptionPartial(partial)
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
                        manager.failUtterance(message: message, kind: .asrFailed)
                    } else if manager.isUtteranceProcessing {
                        manager.finishProcessing(withError: message, kind: .asrFailed)
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
        FlowSessionBridge.setRecordingState(.processing)
        isUtteranceRecording = false
        isUtteranceProcessing = true
        FlowLiveActivityController.update(phase: .processing)

        // Do NOT cancel `asrTask` or `asr` — drain trailing PCM, then finalize.

        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let drainReport = await self.capture.endUtteranceAndDrain()
            FlowDiagnostics.logDrain(drainReport)
            await self.finalizeUtterance()
        }
        debug("utterance stopped, draining tail")
    }

    private func abortUtterance() {
        isUtteranceRecording = false
        isUtteranceProcessing = false
        utteranceRecordingStartedAt = nil
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
        FlowSessionBridge.storeTranscriptionPartial("")
        FlowSessionBridge.setRecordingState(.idle)
        FlowLiveActivityController.update(phase: .idle)
        debug("utterance aborted")
    }

    private func failUtterance(
        message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .asrFailed
    ) {
        isUtteranceRecording = false
        isUtteranceProcessing = false
        utteranceRecordingStartedAt = nil
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
        FlowSessionBridge.storeTranscriptionPartial("")
        FlowSessionBridge.storeTranscriptionError(message, kind: kind)
        FlowSessionBridge.setRecordingState(.idle)
        FlowLiveActivityController.update(phase: .idle)
        debug("utterance failed: \(message)")
    }

    private func finishProcessing(
        withError message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .asrFailed
    ) {
        isUtteranceProcessing = false
        utteranceRecordingStartedAt = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        chunkedPipeline = nil
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        FlowSessionBridge.storeTranscriptionPartial("")
        FlowSessionBridge.storeTranscriptionError(message, kind: kind)
        FlowSessionBridge.setRecordingState(.idle)
        FlowLiveActivityController.update(phase: .idle)
        debug("utterance processing failed: \(message)")
    }

    private func finalizeUtterance() async {
        let pipelineStarted = Date()
        defer {
            isUtteranceProcessing = false
            FlowSessionBridge.setRecordingState(.idle)
            FlowLiveActivityController.update(phase: .idle)
            touchSessionActivity()
        }

        let asrWait = asrWaitTimeout()
        FlowDiagnostics.log(
            "finalize start asrWait=\(Int(asrWait))s engine=\(store.engineMode)"
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
            let kind: FlowSessionKeys.TranscriptionErrorKind =
                (asrTask?.isCancelled == true) ? .recognitionInterrupted : .noSpeech
            FlowDiagnostics.log("finalize failed: empty transcript after \(String(format: "%.1f", asrElapsed))s")
            utteranceRecordingStartedAt = nil
            FlowSessionBridge.storeTranscriptionError(
                AppL10n.string(key),
                kind: kind
            )
            return
        }

        let recordingDuration = consumeRecordingDuration()

        let engineMode = store.engineMode
        let chunkNote = Self.chunkWarningMessage(chunkWarnings)
        // Re-read App Group at finalize so chip-side translation changes
        // from the keyboard extension are visible before polish/translate.
        let pipelineStore = AppGroupStore()

        var delivered = text
        let polishStarted = Date()
        let polishMode = pipelineStore.polishModeForPipeline
        FlowDiagnostics.log(
            "finalize LLM mode=\(Self.polishModeLogLabel(polishMode)) " +
            "translationTarget=\(pipelineStore.translationTargetLocaleId)"
        )
        do {
            let polished = try await polisher.polish(
                text,
                mode: polishMode,
                providerIdOverride: pipelineStore.polishProviderIdOverride
            )
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
            let fallback = Self.makeFallbackDelivery(
                rawText: text,
                error: error,
                engineMode: engineMode,
                chunkWarning: chunkNote
            )
            FlowDiagnostics.log(
                "polish failed after \(String(format: "%.1f", Date().timeIntervalSince(polishStarted)))s: " +
                "\(error.localizedDescription)"
            )
            delivered = fallback.text
            FlowSessionBridge.storeTranscriptionResult(fallback.text, polishWarning: fallback.polishWarning)
        }

        SpeechHistoryStore.shared.recordUtterance(
            text: delivered,
            engineMode: engineMode,
            duration: recordingDuration,
            wasTranslation: pipelineStore.isTranslationEffective
        )

        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        FlowSessionBridge.storeTranscriptionPartial("")
        chunkedPipeline = nil
        debug("utterance finalized length=\(text.count)")
    }

    private static func polishModeLogLabel(_ mode: PolishingService.PolishMode) -> String {
        switch mode {
        case .polish:
            return "polish"
        case .translate(let targetLocaleId):
            return "translate(\(targetLocaleId))"
        }
    }

    private static func chunkWarningMessage(_ warnings: [String]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.joined(separator: "\n")
    }

    private func consumeRecordingDuration() -> TimeInterval {
        defer { utteranceRecordingStartedAt = nil }
        guard let start = utteranceRecordingStartedAt else { return 0 }
        return max(0, Date().timeIntervalSince(start))
    }

    /// v0.2.0: surface the local-mode cloud-polish error path with a
    /// localised hint ("please fill in your DeepSeek key in Settings")
    /// rather than letting the keyboard show a generic network error.
    static func makeFallbackDelivery(
        rawText: String,
        error: Error,
        engineMode: String,
        chunkWarning: String?
    ) -> TranscriptionDelivery {
        let fallbackText = TranscriptPostProcessor.cleanRawASRFallback(rawText)
        let warning = warningFromPolishError(error, engineMode: engineMode)
            ?? polishDegradedWarning()
            ?? chunkWarning
        return TranscriptionDelivery(text: fallbackText, polishWarning: warning)
    }

    private static func warningFromPolishError(_ error: Error, engineMode: String) -> String? {
        if let polishError = error as? PolishingService.PolishError {
            switch polishError {
            case .missingAPIKey:
                if engineMode == "local" {
                    return SharedL10n.string("flow.warning.localPolishUnavailable")
                }
                return SharedL10n.string("flow.warning.cloudPolishMissingKey")
            case .timeout:
                return polishDegradedWarning()
            case .noTranscript:
                return nil
            }
        }
        if error is LLMError {
            return polishDegradedWarning()
        }
        return nil
    }

    private static func polishDegradedWarning() -> String? {
        SharedL10n.string("flow.warning.polishDegraded")
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
