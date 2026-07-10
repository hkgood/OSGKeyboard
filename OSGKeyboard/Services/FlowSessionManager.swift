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
    private let polisher = PolishingService()
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
    private var commandObserver: FlowSessionDarwinObserver?
    /// Last recording state the poll loop observed — logs only on transition.
    private var lastObservedRecordingState: FlowSessionKeys.RecordingState = .idle
    private var activeSessionId: UUID?
    private var currentUtteranceId: UUID?
    private var currentCommandSeq: Int64 = 0
    private var lastHandledCommandSeq: Int64 = 0
    /// Published so Home / debug UI can show "recording" instead of a false "ready".
    @Published private(set) var isUtteranceRecording = false
    /// True from `stopped` until the result/error is written back to App Group.
    @Published private(set) var isUtteranceProcessing = false
    private var finalizeTask: Task<Void, Never>?
    private var asrTask: Task<Void, Never>?
    private var utteranceSafetyTask: Task<Void, Never>?
    private var chunkedPipeline: ChunkedUtterancePipeline?
    private var currentPartial = ""
    private var lastFinal = ""
    private var chunkWarnings: [String] = []
    private var lastReadyTraceSignature = ""
    private var lastCommandFingerprint = ""
    private var lastIgnoredCommandSignature = ""
    /// Wall-clock span of the current mic-open utterance (excludes LLM polish).
    private var utteranceRecordingStartedAt: Date?
    /// True while the host app scene is `.active` — drives foreground renewal.
    private var isAppForeground = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// True while handling a keyboard-initiated `startflow` cold start.
    private var isColdStartHandoff = false
    private var coldStartRecoveryTask: Task<Void, Never>?
    /// Initial proof window — cold mic sessions often need >2.5s after app switch.
    private static let coldStartAudioProofTimeout: TimeInterval = 6
    /// Guards the once-per-process launch reconciliation (scene reconnects
    /// recreate the `@StateObject`-owned manager within the same process).
    private static var didRunLaunchReconciliation = false

    init() {
        // Sessions are (re)started explicitly on app foreground via
        // `activateOnForeground()`. We deliberately do NOT silently reattach a
        // stored session here — after a force-quit that would resurrect capture
        // (and keep a stale Live Activity alive) without the user re-opening.
        //
        // Launch reconciliation: a brand-new process can never own an
        // in-flight session, so whatever the previous generation persisted
        // (force-quit skips `applicationWillTerminate` entirely when the app
        // was suspended) is void. Rotating the generation token also lets the
        // keyboard invalidate stale ready snapshots instantly instead of
        // waiting out the 60 s heartbeat-zombie window.
        //
        // Once per PROCESS, not per manager: iOS can disconnect and later
        // reconnect the sole scene without killing the process, which
        // recreates the `@StateObject` (and thus this init). Re-rotating then
        // would wipe live state that belongs to this very process.
        if AppGroup.isAvailable, !Self.didRunLaunchReconciliation {
            Self.didRunLaunchReconciliation = true
            let previous = FlowSessionBridge.rotateHostGeneration()
            if previous != nil || FlowSessionBridge.isSessionActive() {
                FlowSessionBridge.clearFlowStateOnHostLaunch()
                FlowLiveActivityController.clearOrphanedActivities()
                FlowSessionDarwin.postSessionChanged()
                debug("launch reconciliation: voided previous-generation Flow state")
            }
        }

        capture.onEngineLiveChanged = { [weak self] _ in
            self?.refreshHostReady()
        }
        // A system interruption (call / Siri) stops audio frames mid-utterance;
        // fail fast so the user is not silently recording into a gap.
        capture.onInterruptionBegan = { [weak self] in
            guard let self, self.isUtteranceRecording else { return }
            self.failUtterance(
                message: AppL10n.string("flow.error.recognitionInterrupted"),
                kind: .recognitionInterrupted
            )
        }
        FlowTerminationCoordinator.register(self)
    }

    // MARK: - Public

    /// Starts a Flow session: permissions → continuous capture → App Group active.
    func startSession(duration: TimeInterval? = nil, coldStart: Bool = false) {
        traceState(
            "startSession.request",
            extra: "coldStart=\(coldStart) duration=\(Int(duration ?? FlowSessionPolicy.sessionDuration()))"
        )
        guard AppGroup.isAvailable else {
            debug("cannot start flow session: App Group unavailable")
            return
        }

        if coldStart {
            isColdStartHandoff = true
            showColdStartPreparing()
        }

        reconcilePersistedFlowStateBeforeStart()

        if isActive {
            extendSession(duration: duration)
            refreshHostReady()
            if coldStart {
                Task { @MainActor [weak self] in
                    await self?.prepareExistingSessionForColdStartReturn()
                }
            }
            return
        }

        guard !isStarting else {
            traceState("startSession.ignored", extra: "reason=alreadyStarting")
            return
        }
        // Claim the flag synchronously: on a cold start the URL router and
        // `activateOnForeground()` both fire in the same runloop turn, and
        // setting it inside the async body let two start bodies interleave.
        isStarting = true

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
        // Sweep any Live Activity a previous (force-quit) process left behind
        // *before* we try to (re)start a session. Doing it here — rather than
        // only inside `startSession()`'s success path — means a start that
        // later fails (e.g. mic proof timeout) still clears the stale island
        // instead of leaving a zombie on the lock screen / Dynamic Island.
        // No-op when this process already owns a healthy Live Activity.
        FlowLiveActivityController.clearOrphanedActivities()

        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            FlowSessionBridge.setHostReady(false)
            if isColdStartHandoff {
                showColdStartPermissionFailure()
            }
            FlowLiveActivityController.endSession()
            return
        }
        startSession()
    }

    func dismissColdStartOverlay() {
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        // Clear handoff flags BEFORE any refreshHostReady call. Otherwise
        // refresh → reconcileColdStartOverlayIfRecovered → dismiss → refresh
        // recurses until the main-thread stack overflows (EXC_BAD_ACCESS,
        // "Thread stack size exceeded due to excessive recursion").
        coldStartContext = nil
        isColdStartHandoff = false
        if isActive {
            refreshHostReady()
        }
    }

    func returnToPendingHostFromColdStart() {
        _ = HostReturnService.openPendingHostIfPossible()
        dismissColdStartOverlay()
    }

    func retryColdStartReadiness() {
        guard AppGroup.isAvailable else { return }
        // A failed cold start leaves capture in a running-but-dead state on
        // purpose (the recovery loop keeps probing it). A user-initiated
        // retry must instead begin from a clean pipeline: tear down capture
        // and the cached ASR instance so `startSession` rebuilds both —
        // otherwise the retry reuses the zombie engine and is guaranteed to
        // hit the same audio-proof timeout.
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        if capture.running {
            capture.stop()
        }
        sessionASR?.cancel()
        sessionASR = nil
        sessionASREngineMode = nil
        sessionASRWarmedLocaleID = nil
        startSession(coldStart: true)
    }

    func openColdStartPermissionSettings() {
        AppPermissions.openSystemSettings()
    }

    /// 强杀专用同步 teardown：不等待 ASR/LLM；Live Activity 由
    /// `FlowTerminationCoordinator` 同步 `end`。
    func prepareForProcessTermination() {
        debug("prepareForProcessTermination")

        coldStartContext = nil
        isColdStartHandoff = false
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        startTask?.cancel()
        startTask = nil
        commandObserver = nil
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
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
        asrTask?.cancel()
        asrTask = nil
        chunkedPipeline = nil

        if isUtteranceRecording || isUtteranceProcessing {
            capture.cancelUtterance()
            // `asr` is a computed property that ALLOCATES a fresh ASRService
            // when `sessionASR` is nil — never do that inside the ~5 s
            // termination window; only cancel an instance that exists.
            sessionASR?.cancel()
        }

        capture.cancelUtterance()
        if capture.running {
            capture.stop()
        }

        endBackgroundKeepAlive()
        ScreenWakeLock.release()

        sessionASR?.cancel()
        sessionASR = nil
        sessionASREngineMode = nil
        sessionASRWarmedLocaleID = nil

        if isActive || FlowSessionBridge.isSessionActive() {
            FlowSessionBridge.markSessionInactive()
            FlowSessionDarwin.postSessionChanged()
        }

        activeSessionId = nil
        currentUtteranceId = nil
        currentCommandSeq = 0
        lastHandledCommandSeq = 0
        isUtteranceRecording = false
        isUtteranceProcessing = false
        isActive = false
        isStarting = false
        sessionExpiresAt = nil
        sessionWarning = nil
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        FlowSessionBridge.setHostReady(false)
    }

    func endSession() {
        guard isActive else { return }
        debug("Flow session ended")

        coldStartContext = nil
        isColdStartHandoff = false
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        startTask?.cancel()
        startTask = nil
        commandObserver = nil
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
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil

        if isUtteranceRecording || isUtteranceProcessing {
            capture.cancelUtterance()
            asrTask?.cancel()
            Task { await chunkedPipeline?.cancel() }
            asr.cancel()
        }
        asrTask = nil
        chunkedPipeline = nil
        activeSessionId = nil
        currentUtteranceId = nil
        currentCommandSeq = 0
        lastHandledCommandSeq = 0
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
        // A system interruption (call / Siri) may be in progress. Probe it:
        // `setActive(true)` inside `reassertIfRunning` fails while the
        // interruption is live and succeeds once it ends — which also covers
        // the documented case where iOS never delivers `.ended` (the latch
        // must not depend on that notification, or the session is dead until
        // its TTL). While the probe fails we deliberately do NOT stop or
        // rebuild: tearing the engine down would remove the observers the
        // `.ended` rebuild relies on and churn the shared session mid-call.
        if capture.isInterrupted {
            guard capture.reassertIfRunning(), !capture.isInterrupted else { return }
        }

        if capture.running {
            let reasserted = capture.reassertIfRunning()
            if reasserted, await capture.awaitAudioFlowing(timeout: 2) {
                sessionWarning = nil
                refreshHostReady()
                return
            }
            // The await above is a suspension point: the session may have
            // ended (expiry, user, teardown) while we waited. Never restart
            // the microphone for a session that no longer exists.
            guard isActive, !Task.isCancelled else { return }
            // Never tear capture down underneath a live utterance either — a
            // stalled route transition mid-recording must surface through the
            // utterance pipeline (safety timer / empty-transcript error), not
            // as a silent stop that truncates the take with no error at all.
            guard !isUtteranceRecording, !isUtteranceProcessing else {
                refreshHostReady()
                return
            }
            // Reassert failed, or the engine reports running yet produces no
            // frames (zombie after suspend / mediaserverd reset) — fall
            // through to a full rebuild instead of leaving it half-dead.
            capture.stop()
            debug("capture zombie after foreground — rebuilding")
        }

        do {
            try capture.start()
            sessionWarning = nil
            debug("capture restarted after foreground")
            refreshHostReady()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionWarning = message
            debug("capture restart failed: \(message)")
            refreshHostReady()
        }
    }

    /// Publish whether the keyboard can start a new utterance without jumping to the host app.
    private func refreshHostReady() {
        guard isActive else {
            FlowSessionBridge.writeReadySnapshot(
                FlowReadySnapshot(
                    sessionId: activeSessionId,
                    ready: false,
                    reason: .noSession,
                    engineMode: store.engineMode,
                    localeId: store.localeId,
                    sessionExpiresAt: FlowSessionBridge.sessionExpiresAt(),
                    hostGeneration: FlowSessionBridge.currentHostGeneration()
                )
            )
            return
        }

        let pollingAlive = pollingTask != nil && pollingTask?.isCancelled != true
        let hasRecentAudio = capture.engineHasRecentAudio(maxAge: 2)
        let canAcceptUtterance = capture.engineIsLive
            && pollingAlive
            && hasRecentAudio
            && !isUtteranceRecording
            && !isUtteranceProcessing
            && sessionWarning == nil

        let reason: FlowReadySnapshot.Reason
        if canAcceptUtterance {
            reason = .ready
        } else if sessionWarning != nil {
            reason = .error
        } else if isUtteranceRecording {
            reason = .recording
        } else if isUtteranceProcessing {
            reason = .processing
        } else if !capture.engineIsLive {
            reason = .audioEngineNotLive
        } else if !hasRecentAudio {
            reason = .waitingForAudioProof
        } else {
            reason = .starting
        }

        let now = Date().timeIntervalSince1970
        FlowSessionBridge.writeReadySnapshot(
            FlowReadySnapshot(
                sessionId: activeSessionId,
                ready: canAcceptUtterance,
                reason: reason,
                heartbeatAt: now,
                readyAt: canAcceptUtterance ? now : nil,
                audioProofAt: hasRecentAudio ? now : nil,
                engineMode: store.engineMode,
                localeId: store.localeId,
                busyUtteranceId: isUtteranceRecording || isUtteranceProcessing ? currentUtteranceId : nil,
                sessionExpiresAt: FlowSessionBridge.sessionExpiresAt(),
                hostGeneration: FlowSessionBridge.currentHostGeneration()
            )
        )
        let signature = [
            canAcceptUtterance ? "ready=1" : "ready=0",
            "reason=\(reason.rawValue)",
            capture.engineIsLive ? "engine=live" : "engine=dead",
            hasRecentAudio ? "audio=fresh" : "audio=stale",
            isUtteranceRecording ? "recording=1" : "recording=0",
            isUtteranceProcessing ? "processing=1" : "processing=0",
            sessionWarning == nil ? "warning=0" : "warning=1"
        ].joined(separator: "|")
        if signature != lastReadyTraceSignature {
            lastReadyTraceSignature = signature
            traceState("hostReady.update", extra: signature)
        }
        reconcileColdStartOverlayIfRecovered()
    }

    /// When the host contract turns green while the cold-start overlay still
    /// shows a stale preparing/failed snapshot, heal automatically.
    private func reconcileColdStartOverlayIfRecovered() {
        guard isColdStartHandoff, isActive else { return }
        guard let context = coldStartContext else { return }

        // Mid-utterance is not "ready" — dismiss the ready overlay so Home
        // does not keep advertising "语音已就绪" while utt.rec=1.
        if isUtteranceRecording || isUtteranceProcessing {
            if case .ready = context.state {
                dismissColdStartOverlay()
            }
            return
        }

        guard FlowSessionBridge.isHostReady() else { return }

        switch context.state {
        case .preparing:
            presentColdStartReadyOverlay()
        case .failed:
            sessionWarning = nil
            coldStartRecoveryTask?.cancel()
            coldStartRecoveryTask = nil
            dismissColdStartOverlay()
        case .ready:
            break
        }
    }

    /// Home preview field gained focus while this app is the Flow host.
    /// Reactivate capture and refresh the App Group ready contract so the
    /// custom keyboard extension sees green immediately.
    func refreshForInlineKeyboardFocus() async {
        guard isActive else { return }
        await reactivateCaptureIfNeeded()
        refreshHostReady()
        if !FlowSessionBridge.isHostReady() {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await reactivateCaptureIfNeeded()
            refreshHostReady()
        }
        FlowSessionBridge.writeHeartbeat()
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
        // `isStarting` was claimed synchronously in `startSession()`.
        defer { isStarting = false }
        guard !Task.isCancelled else { return }
        traceState("startSessionAsync.begin")
        sessionWarning = nil

        guard AppPermissions.flowRequirementsMet else {
            sessionWarning = permissionWarningMessage()
            traceState("startSessionAsync.blocked", extra: "reason=permissions")
            FlowSessionBridge.setHostReady(false)
            if isColdStartHandoff {
                showColdStartPermissionFailure()
            }
            isColdStartHandoff = false
            return
        }

        do {
            try capture.start()
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionWarning = message
            traceState("startSessionAsync.failed", extra: "reason=captureStart error=\(message)")
            FlowSessionBridge.setHostReady(false)
            if isColdStartHandoff {
                showColdStartAudioFailure(message: message)
            }
            debug("continuous capture failed: \(message)")
            return
        }

        let audioProved = await waitForAudioProof()
        guard !Task.isCancelled else { return }
        guard audioProved else {
            let message = AppL10n.string("flow.coldStart.error.audioTimeout")
            sessionWarning = message
            traceState("startSessionAsync.failed", extra: "reason=audioProofTimeout")
            FlowSessionBridge.setHostReady(false)
            if isColdStartHandoff {
                showColdStartAudioFailure(message: message)
                scheduleColdStartRecovery(duration: duration)
            } else {
                capture.stop()
            }
            debug("continuous capture did not produce audio frames before timeout")
            return
        }

        activateFlowSessionAfterAudioProof(duration: duration)
        traceState("startSessionAsync.ready")
        debug("Flow session started (\(Int(duration ?? FlowSessionPolicy.sessionDuration()))s inactivity window), continuous capture running")
    }

    private func activateFlowSessionAfterAudioProof(duration: TimeInterval?) {
        let resolvedDuration = duration ?? FlowSessionPolicy.sessionDuration()
        let sessionId = activeSessionId ?? UUID()
        activeSessionId = sessionId
        lastHandledCommandSeq = 0
        FlowSessionBridge.markSessionActive(duration: resolvedDuration, sessionId: sessionId)
        FlowSessionDarwin.postSessionChanged()
        isActive = true
        ScreenWakeLock.acquire()
        sessionExpiresAt = Date().addingTimeInterval(resolvedDuration)

        startHeartbeat()
        startCommandObserver()
        startPolling()
        startLevelPublishing()
        scheduleExpiry(after: resolvedDuration)

        bindSessionASRIfNeeded()
        scheduleASRWarmup()
        FlowLiveActivityController.startSession()

        refreshHostReady()
        traceState("activateFlowSessionAfterAudioProof.done")
    }

    private func prepareExistingSessionForColdStartReturn() async {
        guard isColdStartHandoff, isActive else { return }
        await reactivateCaptureIfNeeded()
        guard await waitForAudioProof() else {
            let message = AppL10n.string("flow.coldStart.error.audioTimeout")
            sessionWarning = message
            FlowSessionBridge.setHostReady(false)
            showColdStartAudioFailure(message: message)
            scheduleColdStartRecovery(duration: nil)
            debug("existing session failed cold-start audio proof")
            return
        }
        sessionWarning = nil
        refreshHostReady()
        handleColdStartAfterSessionReady()
    }

    private func waitForAudioProof() async -> Bool {
        await capture.awaitAudioFlowing(timeout: Self.coldStartAudioProofTimeout)
    }

    @MainActor
    private func handleColdStartAfterSessionReady() {
        guard isColdStartHandoff, isActive else { return }

        refreshHostReady()
        guard FlowSessionBridge.isHostReady() else {
            // Busy ≠ broken: a startflow arriving mid-utterance (e.g. tapping
            // the Live Activity while dictating) finds a healthy session that
            // is simply recording/processing. Showing the audio-failure
            // overlay here would be a lie — and its recovery loop could even
            // stop capture and kill the live utterance.
            if isUtteranceRecording || isUtteranceProcessing {
                dismissColdStartOverlay()
                debug("cold-start handoff ignored: session busy with an utterance")
                return
            }
            let message = AppL10n.string("flow.coldStart.error.audioTimeout")
            sessionWarning = message
            showColdStartAudioFailure(message: message)
            scheduleColdStartRecovery(duration: nil)
            debug("cold-start blocked: host ready contract not published")
            return
        }

        presentColdStartReadyOverlay()
    }

    private func presentColdStartReadyOverlay() {
        let hostEntry = HostReturnService.pendingHostEntry()
        coldStartContext = FlowColdStartContext(hostEntry: hostEntry, state: .ready)
        scheduleAutoReturnToHostIfNeeded(hostEntry: hostEntry)
    }

    private func scheduleAutoReturnToHostIfNeeded(hostEntry: HostAppEntry?) {
        let skipSwitch = FlowSessionPolicy.skipAppSwitch()
        guard skipSwitch, hostEntry != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, self.coldStartContext?.state == .ready else { return }
            if HostReturnService.openPendingHostIfPossible() {
                self.dismissColdStartOverlay()
            }
        }
    }

    /// Actively rebuilds the audio pipeline after a failed cold start instead
    /// of passively waiting for frames that a dead engine will never produce.
    /// Escalates per attempt: reassert the session → full engine rebuild →
    /// bounce the audio session and rebuild. Force-quit relaunches routinely
    /// inherit stale mediaserverd state that only a rebuild clears.
    private func scheduleColdStartRecovery(duration: TimeInterval?) {
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var recovered = false
            for attempt in 1...3 {
                guard !Task.isCancelled, self.isColdStartHandoff else { return }
                switch attempt {
                case 1:
                    _ = self.capture.reassertIfRunning()
                case 2:
                    self.capture.stop()
                    try? self.capture.start()
                default:
                    self.capture.stop()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    try? self.capture.start()
                }
                recovered = await self.capture.awaitAudioFlowing(
                    timeout: TimeInterval(attempt + 1)
                )
                self.traceState(
                    "coldStartRecovery.attempt",
                    extra: "attempt=\(attempt) recovered=\(recovered)"
                )
                if recovered { break }
            }
            guard !Task.isCancelled else { return }
            guard self.isColdStartHandoff else { return }
            guard recovered else {
                // Out of attempts — leave the failure overlay up; its retry
                // button now performs a full teardown so the user always has
                // a working escape hatch (no more force-quit loops). Only
                // tear capture down when no session owns it: for an active
                // session the 1 Hz heartbeat keeps self-healing, and a stop
                // here would just fight it.
                if !self.isActive {
                    self.capture.stop()
                }
                self.traceState("coldStartRecovery.exhausted")
                return
            }

            self.sessionWarning = nil
            self.traceState("coldStartRecovery.recovered")
            if !self.isActive {
                self.activateFlowSessionAfterAudioProof(duration: duration)
            }
            self.refreshHostReady()
        }
    }

    private func showColdStartPreparing() {
        coldStartContext = FlowColdStartContext(
            hostEntry: HostReturnService.pendingHostEntry(),
            state: .preparing
        )
    }

    private func showColdStartPermissionFailure() {
        FlowSessionBridge.setHostReady(false)
        coldStartContext = FlowColdStartContext(
            hostEntry: HostReturnService.pendingHostEntry(),
            state: .failed(.permission(message: permissionWarningMessage()))
        )
    }

    private func showColdStartAudioFailure(message: String) {
        FlowSessionBridge.setHostReady(false)
        coldStartContext = FlowColdStartContext(
            hostEntry: HostReturnService.pendingHostEntry(),
            state: .failed(.audio(message: message))
        )
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

    private func startCommandObserver() {
        commandObserver = FlowSessionDarwinObserver(
            notificationName: FlowSessionDarwin.commandNotificationName
        ) { [weak self] in
            self?.handleKeyboardSignal()
        }
    }

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
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func handleKeyboardSignal() {
        guard let command = FlowSessionBridge.latestCommand() else {
            lastCommandFingerprint = ""
            return
        }
        let fingerprint = "\(command.sessionId.uuidString)|\(command.utteranceId.uuidString)|\(command.action.rawValue)|\(command.commandSeq)"
        guard fingerprint != lastCommandFingerprint else { return }
        lastCommandFingerprint = fingerprint
        handleFlowCommand(command)
    }

    private func handleFlowCommand(_ command: FlowCommand) {
        guard let activeSessionId, command.sessionId == activeSessionId else {
            traceIgnoredCommand(
                reason: "staleSession",
                command: command,
                detail: "commandSession=\(command.sessionId)"
            )
            return
        }
        guard command.commandSeq > lastHandledCommandSeq else {
            traceIgnoredCommand(
                reason: "seqNotIncreasing",
                command: command,
                detail: "last=\(lastHandledCommandSeq)"
            )
            return
        }
        lastHandledCommandSeq = command.commandSeq
        lastIgnoredCommandSignature = ""

        FlowDiagnostics.log(
            "command \(command.action.rawValue) seq=\(command.commandSeq) utterance=\(command.utteranceId)"
        )

        switch command.action {
        case .startRecording:
            guard !isUtteranceRecording, !isUtteranceProcessing else { return }
            beginUtterance(utteranceId: command.utteranceId, commandSeq: command.commandSeq)
        case .stopRecording:
            guard currentUtteranceId == command.utteranceId else { return }
            if isUtteranceRecording {
                endUtterance()
            } else if !isUtteranceProcessing {
                storeCurrentError(
                    AppL10n.string("flow.error.recognitionInterrupted"),
                    kind: .recognitionInterrupted
                )
                debug("stop command without active utterance — notified keyboard")
            }
        case .abort:
            guard currentUtteranceId == command.utteranceId else { return }
            abortUtterance()
        }
    }

    private func storeCurrentPartial(_ text: String) {
        guard let activeSessionId, let currentUtteranceId else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: activeSessionId,
                utteranceId: currentUtteranceId,
                commandSeq: currentCommandSeq,
                status: .partial,
                text: trimmed
            )
        )
    }

    private func storeCurrentFinal(_ text: String, warning: String? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            storeCurrentError(AppL10n.string("flow.error.noSpeech"), kind: .noSpeech)
            return
        }
        guard let activeSessionId, let currentUtteranceId else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: activeSessionId,
                utteranceId: currentUtteranceId,
                commandSeq: currentCommandSeq,
                status: .final,
                text: trimmed,
                warning: warning
            )
        )
    }

    private func storeCurrentError(
        _ message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .generic,
        status: FlowResult.Status = .error
    ) {
        guard let activeSessionId, let currentUtteranceId else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: activeSessionId,
                utteranceId: currentUtteranceId,
                commandSeq: currentCommandSeq,
                status: status,
                text: message,
                errorKind: kind
            )
        )
    }

    private func beginUtterance(utteranceId: UUID? = nil, commandSeq: Int64 = 0) {
        guard capture.engineHasRecentAudio(maxAge: 2) else {
            traceState("beginUtterance.blocked", extra: "reason=audioNotRecent")
            failUtterance(
                message: AppL10n.string("flow.error.audioUnavailable"),
                kind: .audioUnavailable
            )
            return
        }
        guard !isUtteranceProcessing else {
            traceState("beginUtterance.ignored", extra: "reason=processing")
            debug("beginUtterance ignored — previous utterance still processing")
            return
        }
        bindSessionASRIfNeeded()
        let expectedEngine = store.engineMode
        if sessionASREngineMode != expectedEngine {
            traceState(
                "beginUtterance.rebindMismatch",
                extra: "expectedEngine=\(expectedEngine) boundEngine=\(sessionASREngineMode ?? "nil")"
            )
            bindSessionASRIfNeeded(force: true)
        }

        // Usually already warm from session start; refresh without blocking the mic gate.
        scheduleASRWarmup()

        currentUtteranceId = utteranceId ?? UUID()
        currentCommandSeq = commandSeq
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []

        let localeId = store.localeId
        FlowSessionBridge.setTranscriptionLanguage(localeId)
        FlowSessionBridge.clearPendingTranscription()
        FlowSessionBridge.clearResult()

        let locale = SpeechLocaleResolver.resolve(localeId)
        let stream = capture.beginUtterance()
        let pipeline = ChunkedUtterancePipeline(asr: asr, locale: locale)
        chunkedPipeline = pipeline

        isUtteranceRecording = true
        utteranceRecordingStartedAt = Date()
        startUtteranceSafetyTimer()
        refreshHostReady()
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
                    guard let manager else { return }
                    manager.currentPartial = partial
                    manager.storeCurrentPartial(partial)
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

    private func startUtteranceSafetyTimer() {
        utteranceSafetyTask?.cancel()
        let utteranceId = currentUtteranceId
        utteranceSafetyTask = Task { @MainActor [weak self] in
            let timeout = FlowSessionKeys.maxUtteranceDuration + 10
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.isUtteranceRecording, self.currentUtteranceId == utteranceId else { return }
            self.storeCurrentError(
                AppL10n.string("flow.error.recognitionInterrupted"),
                kind: .recognitionInterrupted,
                status: .timeout
            )
            self.abortUtterance()
            self.debug("utterance safety timer aborted stale recording")
        }
    }

    private func endUtterance() {
        guard isUtteranceRecording else { return }

        // Close the mic gate first, then mark processing before dropping the
        // recording flag so the poll loop cannot start a second utterance.
        isUtteranceRecording = false
        isUtteranceProcessing = true
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
        refreshHostReady()
        FlowLiveActivityController.update(phase: .processing)

        // Do NOT cancel `asrTask` or `asr` — drain trailing PCM, then finalize.

        // Capture ids now: a cancelled finalize must still clear *this*
        // utterance's processing gate even if currentUtteranceId was cleared
        // by a racing fail/abort path.
        let drainingSessionId = activeSessionId
        let drainingUtteranceId = currentUtteranceId
        let drainingCommandSeq = currentCommandSeq
        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let drainReport = await self.capture.endUtteranceAndDrain()
            FlowDiagnostics.logDrain(drainReport)
            await self.finalizeUtterance(
                sessionId: drainingSessionId,
                utteranceId: drainingUtteranceId,
                commandSeq: drainingCommandSeq
            )
        }
        debug("utterance stopped, draining tail")
    }

    private func abortUtterance() {
        isUtteranceRecording = false
        isUtteranceProcessing = false
        utteranceRecordingStartedAt = nil
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
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
        currentUtteranceId = nil
        currentCommandSeq = 0
        FlowLiveActivityController.update(phase: .idle)
        refreshHostReady()
        debug("utterance aborted")
    }

    private func failUtterance(
        message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .asrFailed
    ) {
        isUtteranceRecording = false
        isUtteranceProcessing = false
        utteranceRecordingStartedAt = nil
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
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
        storeCurrentError(message, kind: kind)
        currentUtteranceId = nil
        currentCommandSeq = 0
        FlowLiveActivityController.update(phase: .idle)
        refreshHostReady()
        debug("utterance failed: \(message)")
    }

    private func finishProcessing(
        withError message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .asrFailed
    ) {
        isUtteranceProcessing = false
        utteranceRecordingStartedAt = nil
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        chunkedPipeline = nil
        currentPartial = ""
        lastFinal = ""
        chunkWarnings = []
        storeCurrentError(message, kind: kind)
        currentUtteranceId = nil
        currentCommandSeq = 0
        FlowLiveActivityController.update(phase: .idle)
        refreshHostReady()
        debug("utterance processing failed: \(message)")
    }

    private func finalizeUtterance(
        sessionId finalizeSessionId: UUID?,
        utteranceId finalizeUtteranceId: UUID?,
        commandSeq finalizeCommandSeq: Int64
    ) async {
        let pipelineStarted = Date()
        // ALWAYS clear the processing gate for this utterance. The previous
        // guard required currentUtteranceId to still match; a racing
        // fail/abort/cancel path could nil the id (or leave processing stuck)
        // and then skip refreshHostReady — keyboard stayed white forever
        // while host logs still said "utterance finalized".
        defer {
            completeFinalizeCleanup(
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId
            )
        }

        let asrWait = asrWaitTimeout()
        FlowDiagnostics.log(
            "finalize start asrWait=\(Int(asrWait))s engine=\(store.engineMode)"
        )

        let asrDeadline = Date().addingTimeInterval(asrWait)
        while Date() < asrDeadline {
            if !lastFinal.isEmpty { break }
            if asrTask?.isCancelled == true { break }
            // Honour cooperative cancel so a replaced finalize exits promptly,
            // but still run defer cleanup (unlike an early `return` mid-polish
            // that used to leave processing=true when ids no longer matched).
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if lastFinal.isEmpty {
            FlowDiagnostics.log("ASR wait elapsed — cancelling ASR task and using best available transcript")
            asrTask?.cancel()
            Task { await chunkedPipeline?.cancel() }
        }

        let asrElapsed = Date().timeIntervalSince(pipelineStarted)
        FlowDiagnostics.log("ASR phase done in \(String(format: "%.1f", asrElapsed))s finalLen=\(lastFinal.count)")

        var text = lastFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            text = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else {
            let key = (asrTask?.isCancelled == true || Task.isCancelled)
                ? "flow.error.recognitionInterrupted"
                : "flow.error.noSpeech"
            let kind: FlowSessionKeys.TranscriptionErrorKind =
                (asrTask?.isCancelled == true || Task.isCancelled)
                ? .recognitionInterrupted : .noSpeech
            FlowDiagnostics.log("finalize failed: empty transcript after \(String(format: "%.1f", asrElapsed))s")
            utteranceRecordingStartedAt = nil
            storeFinalizedError(
                AppL10n.string(key),
                kind: kind,
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId,
                commandSeq: finalizeCommandSeq
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
            // If the finalize task was cancelled (cold-start churn / abort),
            // skip the LLM round-trip and deliver the raw transcript so the
            // keyboard is not left waiting on a result that never arrives.
            if Task.isCancelled {
                throw CancellationError()
            }
            let polished = try await polisher.polish(
                text,
                mode: polishMode,
                providerIdOverride: pipelineStore.polishProviderIdOverride
            )
            delivered = polished
            storeFinalizedResult(
                polished,
                warning: chunkNote,
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId,
                commandSeq: finalizeCommandSeq
            )
            FlowDiagnostics.log(
                "polish done in \(String(format: "%.1f", Date().timeIntervalSince(polishStarted)))s " +
                "total=\(String(format: "%.1f", Date().timeIntervalSince(pipelineStarted)))s"
            )
        } catch {
            // CancellationError is common when the user jumps back via
            // startflow mid-polish; still deliver raw text. Other errors
            // keep the existing polish-warning fallback.
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
            storeFinalizedResult(
                fallback.text,
                warning: fallback.polishWarning,
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId,
                commandSeq: finalizeCommandSeq
            )
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
        chunkedPipeline = nil
        debug("utterance finalized length=\(text.count)")
    }

    /// Drop the processing gate and republish hostReady after finalize.
    /// Must not depend on a perfect id match — a racing fail/abort/cancel
    /// used to skip this block and leave the keyboard stuck on white「识别中」
    /// even after "utterance finalized" was logged.
    private func completeFinalizeCleanup(sessionId: UUID?, utteranceId: UUID?) {
        // A newer utterance may have started; never clobber its gate.
        if let current = currentUtteranceId,
           let finished = utteranceId,
           current != finished {
            debug(
                "finalize cleanup skipped — newer utterance live " +
                "finished=\(finished.uuidString.prefix(8)) current=\(current.uuidString.prefix(8))"
            )
            return
        }

        let wasProcessing = isUtteranceProcessing
        isUtteranceProcessing = false
        FlowLiveActivityController.update(phase: .idle)
        if isActive {
            touchSessionActivity()
        }
        if currentUtteranceId == utteranceId || currentUtteranceId == nil {
            currentUtteranceId = nil
            currentCommandSeq = 0
        }
        refreshHostReady()
        debug(
            "finalize cleanup done wasProcessing=\(wasProcessing ? 1 : 0) " +
            "utterance=\(utteranceId?.uuidString.prefix(8) ?? "nil") " +
            "session=\(sessionId?.uuidString.prefix(8) ?? "nil")"
        )
    }

    private func storeFinalizedResult(
        _ text: String,
        warning: String?,
        sessionId: UUID?,
        utteranceId: UUID?,
        commandSeq: Int64
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            storeFinalizedError(
                AppL10n.string("flow.error.noSpeech"),
                kind: .noSpeech,
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq
            )
            return
        }
        guard let sessionId, let utteranceId else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: .final,
                text: trimmed,
                warning: warning
            )
        )
    }

    private func storeFinalizedError(
        _ message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind,
        sessionId: UUID?,
        utteranceId: UUID?,
        commandSeq: Int64,
        status: FlowResult.Status = .error
    ) {
        guard let sessionId, let utteranceId else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: status,
                text: message,
                errorKind: kind
            )
        )
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
        TranscriptionPolishFallback.makeDelivery(
            rawText: rawText,
            error: error,
            engineMode: engineMode,
            chunkWarning: chunkWarning
        )
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
            // Refresh the Live Activity `staleDate` every N heartbeat ticks
            // (1 Hz) — well inside `FlowLiveActivityController.staleWindow` so a
            // live session never looks stale, while a force-quit stops these
            // refreshes and lets the island go stale within ~30 s.
            let liveActivityKeepAliveEveryTicks = 10
            var tick = 0
            while !Task.isCancelled {
                guard let self else { break }
                if self.isActive, !self.capture.engineIsLive {
                    await self.reactivateCaptureIfNeeded()
                }
                FlowSessionBridge.writeHeartbeat()
                self.refreshHostReady()
                tick += 1
                if tick % liveActivityKeepAliveEveryTicks == 0 {
                    FlowLiveActivityController.keepAlive()
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.isActive else { break }
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

    // MARK: - Temporary Flow debug panel (remove after orange-mic investigation)

    /// Snapshot for the on-screen debug panel. Safe to call from the main actor.
    func makeDebugRows() -> [FlowDebugRow] {
        let snapshot = FlowSessionBridge.readySnapshot()
        let hostRows = FlowDebugAppGroupSnapshot.rows()
        let memRows: [FlowDebugRow] = [
            FlowDebugRow("isActive", isActive ? "1" : "0"),
            FlowDebugRow("isStarting", isStarting ? "1" : "0"),
            FlowDebugRow("coldStart", isColdStartHandoff ? "1" : "0"),
            FlowDebugRow("engineLive", capture.engineIsLive ? "1" : "0"),
            FlowDebugRow("audioFresh", capture.engineHasRecentAudio(maxAge: 2) ? "1" : "0"),
            FlowDebugRow("mem.reason", snapshot?.reason.rawValue ?? "nil"),
            FlowDebugRow("utt.rec", isUtteranceRecording ? "1" : "0"),
            FlowDebugRow("utt.proc", isUtteranceProcessing ? "1" : "0"),
            FlowDebugRow("sessionId", activeSessionId.map { String($0.uuidString.prefix(8)) } ?? "nil"),
            FlowDebugRow("warning", sessionWarning == nil ? "0" : "1"),
            FlowDebugRow("overlay", coldStartContext.map { String(describing: $0.state) } ?? "nil"),
            FlowDebugRow("bridgeReady", FlowSessionBridge.isHostReady() ? "1" : "0")
        ]
        // Prefer App Group snap.reason near the top of the shared block.
        return memRows + hostRows
    }

    private func traceIgnoredCommand(reason: String, command: FlowCommand, detail: String) {
        let signature = "\(reason)|\(command.action.rawValue)|\(command.commandSeq)|\(command.sessionId.uuidString)|\(command.utteranceId.uuidString)|\(detail)"
        guard signature != lastIgnoredCommandSignature else { return }
        lastIgnoredCommandSignature = signature
        traceState(
            "command.ignored",
            extra: "reason=\(reason) action=\(command.action.rawValue) seq=\(command.commandSeq) \(detail)"
        )
    }

    private func traceState(_ event: String, extra: String? = nil) {
        let staleness = FlowSessionBridge.heartbeatStaleness().map { String(format: "%.1f", $0) } ?? "nil"
        let sessionId = activeSessionId?.uuidString ?? "nil"
        let utteranceId = currentUtteranceId?.uuidString ?? "nil"
        let summary = [
            "event=\(event)",
            "active=\(isActive)",
            "starting=\(isStarting)",
            "coldStart=\(isColdStartHandoff)",
            "sessionId=\(sessionId)",
            "utteranceId=\(utteranceId)",
            "cmdSeq=\(currentCommandSeq)",
            "lastCmd=\(lastHandledCommandSeq)",
            "recording=\(isUtteranceRecording)",
            "processing=\(isUtteranceProcessing)",
            "storeEngine=\(store.engineMode)",
            "boundEngine=\(sessionASREngineMode ?? "nil")",
            "engineLive=\(capture.engineIsLive)",
            "hostReady=\(FlowSessionBridge.isHostReady())",
            "sessionActive=\(FlowSessionBridge.isSessionActive())",
            "heartbeatStaleness=\(staleness)"
        ].joined(separator: " ")
        if let extra, !extra.isEmpty {
            debug("[trace] \(summary) \(extra)")
        } else {
            debug("[trace] \(summary)")
        }
    }
}
