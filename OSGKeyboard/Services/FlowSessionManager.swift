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
import OSGKeyboardHostSupport

struct FlowUtteranceStartToken: Equatable, Sendable {
    let generation: UInt64
    let utteranceId: UUID
}

enum FlowUtteranceLifecyclePolicy {
    static func canContinueStart(
        token: FlowUtteranceStartToken,
        currentGeneration: UInt64,
        currentUtteranceId: UUID?,
        terminalUtteranceIds: Set<UUID>
    ) -> Bool {
        currentGeneration == token.generation
            && currentUtteranceId == token.utteranceId
            && !terminalUtteranceIds.contains(token.utteranceId)
    }
}

@MainActor
final class FlowSessionManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var sessionExpiresAt: Date?
    /// Non-nil when continuous capture failed or permissions are missing.
    @Published private(set) var sessionWarning: String?

    private let capture = FlowContinuousCapture()
    private let pipController = FlowPictureInPictureController()
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
    private var levelTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var audioPrimeTask: Task<Bool, Never>?
    private var audioPrimeID: UUID?
    private var audioPrimeCancellationRequested = false
    private var startupAudioHealthTask: Task<Void, Never>?
    private var didRunStartupAudioHealthCheck = false
    private var commandObserver: FlowSessionDarwinObserver?
    /// Last recording state the poll loop observed — logs only on transition.
    private var lastObservedRecordingState: FlowSessionKeys.RecordingState = .idle
    private var activeSessionId: UUID?
    private var currentUtteranceId: UUID?
    /// Claimed synchronously before any async capture work begins.
    private var startingUtteranceId: UUID?
    private var startTransactionDeadlineAt: TimeInterval?
    /// Monotonic token captured by every async worker for one utterance.
    private var utteranceGeneration: UInt64 = 0
    /// Terminal delivery is idempotent: only the first path may write a result.
    private var terminalUtteranceIds: Set<UUID> = []
    /// Cursor context captured by the keyboard at the final insertion point.
    private var pendingFieldContext: FlowFieldContext?
    /// Dictation vs explicit last-input editing for the live utterance.
    private var currentUtteranceMode: FlowUtteranceMode = .dictation
    private var pendingEditSourceText: String?
    private var pendingSourceHistoryEntryID: UUID?
    private var pendingSourceHistoryEntryRevision: Int64?
    private var pendingProcessingDeadlineAt: TimeInterval?
    private var pendingStopUtteranceId: UUID?
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
    private var lastFinalWithPauseMarks = ""
    /// Partial stitched text captured when the user stops recording.
    private var bestPartialSnapshot = ""
    /// Full utterance PCM for batch ASR fallback after pipelined chunking.
    private var utterancePCMSamples: [Float] = []
    private var chunkWarnings: [String] = []
    private var asrCompletedGeneration: UInt64?
    private var asrFailureMessage: String?
    private var lastReadyTraceSignature = ""
    private var lastCommandFingerprint = ""
    private var lastIgnoredCommandSignature = ""
    /// Wall-clock span of the current mic-open utterance (excludes LLM polish).
    private var utteranceRecordingStartedAt: Date?
    /// True while the host app scene is `.active` — drives foreground renewal.
    private var isAppForeground = false
    /// True while handling a keyboard-initiated `startflow` cold start.
    private var isColdStartHandoff = false
    private var coldStartRecoveryTask: Task<Void, Never>?
    var shouldDeferHostHeavyWork: Bool {
        startingUtteranceId != nil
            || isUtteranceRecording
            || isUtteranceProcessing
            || hasUnacknowledgedTerminalResult()
    }

    func attachPiPHostView(_ view: UIView) {
        pipController.attachHostView(view)
    }

    /// Guards the once-per-process launch reconciliation (scene reconnects
    /// recreate the `@StateObject`-owned manager within the same process).
    private static var didRunLaunchReconciliation = false

    init() {
        // Sessions are (re)started explicitly on app foreground via
        // `activateOnForeground()`. We deliberately do NOT silently reattach a
        // stored session here — after a force-quit that would resurrect capture
        // without the user re-opening.
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
                FlowSessionDarwin.postSessionChanged()
                debug("launch reconciliation: voided previous-generation Flow state")
            }
        }

        capture.onEngineLiveChanged = { [weak self] live in
            guard let self else { return }
            self.refreshHostReady()
            if !live, self.isUtteranceRecording {
                self.failUtterance(
                    message: AppL10n.string("flow.error.audioUnavailable"),
                    kind: .audioUnavailable
                )
            }
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
        pipController.onUserDismissed = { [weak self] in
            guard let self, self.isActive else { return }
            self.debug("PiP dismissed by user — ending Flow session")
            self.endSession()
        }
        FlowTerminationCoordinator.register(self)
    }

    // MARK: - Public

    /// Starts a Flow session: permissions → continuous capture → App Group active.
    func startSession(
        duration: TimeInterval? = nil,
        coldStart: Bool = false,
        reason: String = "unspecified"
    ) {
        OSGDiag.log(
            "startSession.request reason=\(reason) coldStart=\(coldStart) "
                + "active=\(isActive) starting=\(isStarting) \(OSGDiag.memoryTag())",
            category: "flow"
        )
        traceState(
            "startSession.request",
            extra: "coldStart=\(coldStart) reason=\(reason)"
        )
        guard AppGroup.isAvailable else {
            debug("cannot start flow session: App Group unavailable")
            return
        }

        reconcilePersistedFlowStateBeforeStart()

        // Healthy / busy sessions must not flash the cold-start overlay when a
        // spurious `startflow` arrives (e.g. keyboard finalize race).
        if coldStart, isActive {
            extendSession(duration: duration)
            refreshHostReady()
            let decision = FlowHandoffPolicy.coldStartOverlayDecision(
                sessionIsActive: true,
                hostIsReady: FlowSessionBridge.isHostReady(),
                isUtteranceBusy: isUtteranceRecording || isUtteranceProcessing
            )
            switch decision {
            case .silence:
                traceState(
                    "startSession.coldStart.silenced",
                    extra: FlowSessionBridge.isHostReady() ? "reason=alreadyReady" : "reason=busy"
                )
                return
            case .present:
                isColdStartHandoff = true
                Task { @MainActor [weak self] in
                    await self?.prepareExistingSessionForColdStartReturn()
                }
                return
            }
        }

        if coldStart {
            isColdStartHandoff = true
        }

        if isActive {
            extendSession(duration: duration)
            refreshHostReady()
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
        switch FlowOrphanRecordingReconciler.decide(
            isHostStale: FlowSessionBridge.isHostStale(),
            isActive: isActive,
            recordingState: FlowSessionBridge.recordingState()
        ) {
        case .clearZombieSession:
            if isActive {
                endSession()
            } else {
                FlowSessionBridge.clearFlowState()
            }
            debug("reconciled zombie persisted Flow state")
        case .clearOrphanedRecording(let orphaned):
            FlowSessionBridge.setRecordingState(.idle)
            FlowSessionBridge.clearPendingTranscription()
            debug("cleared orphaned keyboard recording state: \(orphaned.rawValue)")
        case .none:
            break
        }
    }

    /// Foreground entry for Flow.
    ///
    /// Default is **light** for audio work: automatically arm the low-profile
    /// PiP, but do not
    /// start capture or ASR. The transparent PiP is intentionally cheap; the
    /// 170–220 MB capture/model path still starts only on explicit speech.
    ///
    /// Pass `startCapture: true` for explicit user intent (Home “Start”, etc.).
    /// Keyboard mic cold-start uses `osgkeyboard://startflow` → `startSession`.
    func activateOnForeground(
        reason: String = "unspecified",
        startCapture: Bool = false
    ) {
        OSGDiag.log(
            "activateOnForeground reason=\(reason) startCapture=\(startCapture) "
                + "onboardingDone=\(ProviderConfig.shared.hasCompletedOnboarding) "
                + "\(OSGDiag.memoryTag())",
            category: "flow"
        )
        guard AppGroup.isAvailable else {
            OSGDiag.log("activateOnForeground aborted reason=appGroupUnavailable", category: "flow")
            return
        }
        guard AppPermissions.flowRequirementsMet else {
            OSGDiag.log("activateOnForeground aborted reason=permissions", category: "flow")
            sessionWarning = permissionWarningMessage()
            FlowSessionBridge.setHostReady(false)
            return
        }

        startSession(
            reason: !startCapture
                ? "activateOnForeground.autoPiP:\(reason)"
                : "activateOnForeground:\(reason)"
        )
    }

    private func completeColdStartHandoff() {
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        isColdStartHandoff = false
        if isActive {
            refreshHostReady()
        }
    }

    /// 强杀专用同步 teardown：不等待 ASR/LLM。
    func prepareForProcessTermination() {
        debug("prepareForProcessTermination")
        if isUtteranceRecording || isUtteranceProcessing,
           claimTerminal(utteranceId: currentUtteranceId) {
            storeCurrentError(
                AppL10n.string("flow.error.recognitionInterrupted"),
                kind: .recognitionInterrupted,
                status: .aborted
            )
        }

        isColdStartHandoff = false
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        startTask?.cancel()
        startTask = nil
        startupAudioHealthTask?.cancel()
        startupAudioHealthTask = nil
        audioPrimeTask?.cancel()
        audioPrimeTask = nil
        audioPrimeID = nil
        audioPrimeCancellationRequested = false
        commandObserver = nil
        pollingTask?.cancel()
        pollingTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
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
        pipController.stop()

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
        pendingFieldContext = nil
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
        lastFinalWithPauseMarks = ""
        bestPartialSnapshot = ""
        utterancePCMSamples = []
        chunkWarnings = []
        FlowSessionBridge.setHostReady(false)
    }

    func endSession() {
        guard isActive else { return }
        debug("Flow session ended")
        if isUtteranceRecording || isUtteranceProcessing,
           claimTerminal(utteranceId: currentUtteranceId) {
            storeCurrentError(
                AppL10n.string("flow.error.recognitionInterrupted"),
                kind: .recognitionInterrupted,
                status: .aborted
            )
        }

        isColdStartHandoff = false
        coldStartRecoveryTask?.cancel()
        coldStartRecoveryTask = nil
        startTask?.cancel()
        startTask = nil
        startupAudioHealthTask?.cancel()
        startupAudioHealthTask = nil
        audioPrimeTask?.cancel()
        audioPrimeTask = nil
        audioPrimeID = nil
        audioPrimeCancellationRequested = false
        commandObserver = nil
        pollingTask?.cancel()
        pollingTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
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
        pendingFieldContext = nil
        currentCommandSeq = 0
        lastHandledCommandSeq = 0
        isUtteranceRecording = false
        isUtteranceProcessing = false

        capture.stop()
        pipController.stop()
        ScreenWakeLock.release()
        sessionASR = nil
        sessionASREngineMode = nil
        sessionASRWarmedLocaleID = nil
        FlowSessionBridge.markSessionInactive()
        FlowSessionDarwin.postSessionChanged()
        isActive = false
        sessionExpiresAt = nil
        sessionWarning = nil
        currentPartial = ""
        lastFinal = ""
        lastFinalWithPauseMarks = ""
    }

    func extendSession(duration: TimeInterval? = nil) {
        _ = duration
        refreshHostReady()
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
            if isActive {
                Task { @MainActor [weak self] in
                    await self?.pipController.prepareForBackgroundAutoStart()
                }
            }
        case .background:
            setAppForeground(false)
            if isActive {
                Task { @MainActor [weak self] in
                    await self?.pipController.prepareForBackgroundAutoStart()
                }
            }
            if isColdStartHandoff {
                completeColdStartHandoff()
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
    }

    private func resumeAfterForeground() {
        guard isActive else {
            return
        }

        FlowSessionBridge.writeHeartbeat()

        Task { @MainActor [weak self] in
            await self?.reactivateCaptureIfNeeded()
            // v0.2.0: iOS `SpeechAnalyzer` is bundled with the OS; no
            // on-device weights to reload after a background trip.
            self?.bindSessionASRIfNeeded()
            // ASR warmup stays on first mic press — never on foreground bounce.
        }
    }

    private func reactivateCaptureIfNeeded() async {
        guard isActive else { return }
        // PiP releases the mic between utterances (and after drain while
        // processing). Only reassert when an utterance is actively recording
        // with capture already running — otherwise a foreground bounce was
        // cold-starting the mic mid-finalize (`!pri` / session churn).
        guard isUtteranceRecording, capture.running else {
            refreshHostReady()
            return
        }
        // A system interruption (call / Siri) may be in progress. Probe it:
        // `setActive(true)` inside `reassertIfRunning` fails while the
        // interruption is live and succeeds once it ends — which also covers
        // the documented case where iOS never delivers `.ended` (the latch
        // must not depend on that notification, or the session is dead until
        // its TTL). While the probe fails we deliberately do NOT stop or
        // rebuild: tearing the engine down would remove the observers the
        // `.ended` rebuild relies on and churn the shared session mid-call.
        if capture.isInterrupted {
            guard await capture.reassertIfRunning(), !capture.isInterrupted else { return }
        }

        if capture.running {
            let reasserted = await capture.reassertIfRunning()
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
            try await capture.start()
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
                    hostGeneration: FlowSessionBridge.currentHostGeneration()
                )
            )
            return
        }

        let pollingAlive = pollingTask != nil && pollingTask?.isCancelled != true
        let hasRecentAudio = capture.engineHasRecentAudio(maxAge: 2)
        let hasPendingDelivery = hasUnacknowledgedTerminalResult()
        let canAcceptUtterance = pipController.isPictureInPictureActive
            && pollingAlive
            && startingUtteranceId == nil
            && !isUtteranceRecording
            && !isUtteranceProcessing
            && sessionWarning == nil
            && !capture.isInterrupted
            && !hasPendingDelivery

        let reason: FlowReadySnapshot.Reason
        if canAcceptUtterance {
            reason = .ready
        } else if startingUtteranceId != nil {
            reason = .waitingForAudioProof
        } else if sessionWarning != nil {
            reason = .error
        } else if isUtteranceRecording {
            reason = .recording
        } else if isUtteranceProcessing {
            reason = .processing
        } else if hasPendingDelivery {
            reason = .awaitingDelivery
        } else if !pipController.isPictureInPictureActive {
            reason = .starting
        } else if pipController.isPictureInPictureActive {
            // PiP is already up — transient gates (!polling / interruption)
            // are not a cold start. Prefer awaitingDelivery-adjacent idle over
            // `.starting` so the keyboard never flashes a false “starting” state.
            reason = .awaitingDelivery
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
                busyUtteranceId: startingUtteranceId
                    ?? (isUtteranceRecording || isUtteranceProcessing
                        ? currentUtteranceId
                        : (hasPendingDelivery ? FlowSessionBridge.latestResult()?.utteranceId : nil)),
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
            startingUtteranceId == nil ? "starting=0" : "starting=1",
            sessionWarning == nil ? "warning=0" : "warning=1"
        ].joined(separator: "|")
        if signature != lastReadyTraceSignature {
            lastReadyTraceSignature = signature
            traceState("hostReady.update", extra: signature)
        }
    }

    /// Home preview field gained focus while this app is the Flow host.
    /// Reactivate capture and refresh the App Group ready contract so the
    /// custom keyboard extension sees green immediately.
    func refreshForInlineKeyboardFocus() async {
        guard isActive else { return }
        refreshHostReady()
        FlowSessionBridge.writeHeartbeat()
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
            isColdStartHandoff = false
            return
        }

        switch await pipController.startAndWait() {
        case .started:
            activateFlowSessionAfterPiPProof(duration: duration)
            traceState("startSessionAsync.ready")
            debug("Flow session started (PiP keep-alive), mic released between utterances")
        case .failed(let failure):
            let message = AppL10n.string(failure.localizationKey)
            sessionWarning = message
            traceState("startSessionAsync.failed", extra: "reason=pipUnavailable failure=\(failure)")
            FlowSessionBridge.setHostReady(false)
            if isColdStartHandoff {
                scheduleColdStartRecovery(duration: duration)
            }
            debug("PiP keep-alive failed to start: \(failure)")
        }
    }

    private func activateFlowSessionAfterPiPProof(duration: TimeInterval?) {
        let sessionId = activeSessionId ?? UUID()
        activeSessionId = sessionId
        lastHandledCommandSeq = 0
        FlowSessionBridge.markSessionActivePersistent(sessionId: sessionId)
        FlowSessionDarwin.postSessionChanged()
        isActive = true
        // Low-profile PiP is a system-owned keep-alive surface. Keeping the
        // display awake wastes far more power than the static PiP itself.
        ScreenWakeLock.release()
        sessionExpiresAt = nil

        startHeartbeat()
        startCommandObserver()
        startPolling()
        startLevelPublishing()

        bindSessionASRIfNeeded()
        // ASR warmup deferred to beginUtterance (first mic press).

        refreshHostReady()
        scheduleStartupAudioHealthCheck()
        traceState("activateFlowSessionAfterPiPProof.done")
    }

    private func scheduleStartupAudioHealthCheck() {
        guard !didRunStartupAudioHealthCheck else { return }
        didRunStartupAudioHealthCheck = true
        startupAudioHealthTask?.cancel()
        startupAudioHealthTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Let deterministic Rime deployment claim the launch memory peak.
            // The health probe is opportunistic and must never delay app UI.
            try? await Task.sleep(nanoseconds: 300_000_000)
            let heavyDeadline = Date().addingTimeInterval(8)
            while FlowSessionBridge.isHostHeavy(), Date() < heavyDeadline {
                guard self.isActive, !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard self.isActive,
                  !Task.isCancelled,
                  AppPermissions.flowRequirementsMet,
                  !FlowSessionBridge.isHostHeavy(),
                  self.startingUtteranceId == nil,
                  !self.isUtteranceRecording,
                  !self.isUtteranceProcessing,
                  !self.hasUnacknowledgedTerminalResult() else {
                FlowDiagnostics.log("startup audio health check skipped")
                return
            }
            await self.runStartupAudioHealthCheck()
        }
    }

    private func runStartupAudioHealthCheck() async {
        let healthID = UUID()
        startAudioPrime(id: healthID, origin: "startupHealth")
        guard let task = audioPrimeTask else { return }
        _ = await task.value
        guard isActive, !Task.isCancelled else { return }

        // If a user utterance or touch prime took ownership, it has priority.
        guard audioPrimeID == healthID,
              startingUtteranceId == nil,
              !isUtteranceRecording,
              !isUtteranceProcessing else {
            FlowDiagnostics.log("startup audio health check adopted by user")
            return
        }

        var flowing = await capture.awaitAudioFlowing(timeout: 1.2)
        if !flowing {
            // One bounded rebuild exercises the same soft-dead recovery as a
            // real first utterance, before the user is waiting on it.
            capture.stop(releaseSession: false)
            audioPrimeTask = nil
            startAudioPrime(id: healthID, origin: "startupHealthRebuild")
            if let rebuild = audioPrimeTask {
                _ = await rebuild.value
                flowing = await capture.awaitAudioFlowing(timeout: 1.0)
            }
        }

        guard audioPrimeID == healthID,
              startingUtteranceId == nil,
              !isUtteranceRecording,
              !isUtteranceProcessing else {
            FlowDiagnostics.log("startup audio health rebuild adopted by user")
            return
        }
        audioPrimeID = nil
        audioPrimeTask = nil
        audioPrimeCancellationRequested = false
        if capture.running {
            capture.stop(releaseSession: false)
        }
        _ = await pipController.reassertKeepAliveAudioSession()
        refreshHostReady()
        FlowDiagnostics.log(
            "startup audio health check done flowing=\(flowing ? 1 : 0)"
        )
    }

    private func prepareExistingSessionForColdStartReturn() async {
        guard isColdStartHandoff, isActive else { return }
        sessionWarning = nil
        if !pipController.isPictureInPictureActive {
            switch await pipController.startAndWait() {
            case .started:
                break
            case .failed(let failure):
                let message = AppL10n.string(failure.localizationKey)
                sessionWarning = message
                FlowSessionBridge.setHostReady(false)
                scheduleColdStartRecovery(duration: nil)
                debug("existing PiP session failed cold-start restart: \(failure)")
                return
            }
        }
        refreshHostReady()
        handleColdStartAfterSessionReady()
    }

    @MainActor
    private func handleColdStartAfterSessionReady() {
        guard isColdStartHandoff, isActive else { return }

        refreshHostReady()
        guard FlowSessionBridge.isHostReady() else {
            // Busy ≠ broken: a startflow arriving mid-utterance finds a healthy
            // session that is simply recording/processing. Treating it as a
            // PiP failure could restart capture and kill the live utterance.
            if isUtteranceRecording || isUtteranceProcessing {
                completeColdStartHandoff()
                debug("cold-start handoff ignored: session busy with an utterance")
                return
            }
            let message = AppL10n.string("flow.session.error.notPossible")
            sessionWarning = message
            FlowSessionBridge.setHostReady(false)
            scheduleColdStartRecovery(duration: nil)
            debug("cold-start blocked: host ready contract not published")
            return
        }

        let hostEntry = HostReturnService.pendingHostEntry()
        guard hostEntry != nil else {
            completeColdStartHandoff()
            return
        }
        scheduleAutoReturnToHostIfNeeded(hostEntry: hostEntry)
    }

    private func scheduleAutoReturnToHostIfNeeded(hostEntry: HostAppEntry?) {
        let skipSwitch = true
        guard skipSwitch, hostEntry != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self, self.isColdStartHandoff, self.isActive,
                  FlowSessionBridge.isHostReady() else { return }
            if HostReturnService.openPendingHostIfPossible() {
                self.completeColdStartHandoff()
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
            let outcome = await self.pipController.startAndWait()
            self.traceState("coldStartRecovery.pip", extra: "outcome=\(outcome)")
            guard !Task.isCancelled, self.isColdStartHandoff else { return }
            switch outcome {
            case .started:
                if self.isActive {
                    self.sessionWarning = nil
                    self.refreshHostReady()
                    self.handleColdStartAfterSessionReady()
                } else {
                    self.activateFlowSessionAfterPiPProof(duration: duration)
                    self.handleColdStartAfterSessionReady()
                }
            case .failed(let failure):
                self.sessionWarning = AppL10n.string(failure.localizationKey)
            }
        }
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
        let localeID = SpeechLocaleResolver.resolve(store.localeId).identifier(.bcp47)
        guard sessionASRWarmedLocaleID != localeID else { return }
        guard HostMemoryBudget.gate("asr.warmup", category: "asr") else { return }
        OSGDiag.log("scheduleASRWarmup \(OSGDiag.memoryTag())", category: "asr")
        FlowSessionBridge.setHostHeavy(true)
        Task { @MainActor [weak self] in
            defer { FlowSessionBridge.setHostHeavy(false) }
            await self?.warmupASRIfNeeded()
        }
    }

    private func warmupASRIfNeeded() async {
        OSGDiag.log("warmupASRIfNeeded.begin \(OSGDiag.memoryTag())", category: "asr")
        bindSessionASRIfNeeded()
        let locale = SpeechLocaleResolver.resolve(store.localeId)
        let localeID = locale.identifier(.bcp47)
        guard sessionASRWarmedLocaleID != localeID else {
            OSGDiag.log("warmupASRIfNeeded.skip alreadyWarmed=\(localeID)", category: "asr")
            return
        }
        await asr.warmup(locale: locale)
        sessionASRWarmedLocaleID = localeID
        FlowDiagnostics.log("ASR warmup complete locale=\(localeID)")
        OSGDiag.log("warmupASRIfNeeded.done locale=\(localeID) \(OSGDiag.memoryTag())", category: "asr")
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
        FlowSessionBridge.reloadFromDisk()
        consumeHistoryMutationOutbox()
        var commands = FlowSessionBridge.commands(after: lastHandledCommandSeq)
        if commands.isEmpty, let latest = FlowSessionBridge.latestCommand(),
           latest.commandSeq > lastHandledCommandSeq {
            commands = [latest]
        }
        guard !commands.isEmpty else {
            lastCommandFingerprint = ""
            consumeAckIfNeeded()
            return
        }
        for command in commands {
            let fingerprint = "\(command.sessionId.uuidString)|\(command.utteranceId.uuidString)|\(command.action.rawValue)|\(command.commandSeq)"
            guard fingerprint != lastCommandFingerprint else { continue }
            lastCommandFingerprint = fingerprint
            handleFlowCommand(command)
        }
        consumeAckIfNeeded()
    }

    private func consumeHistoryMutationOutbox() {
        for mutation in HistoryMutationOutbox.pending() {
            let entry = SpeechHistoryStore.shared.applyHistoryMutation(mutation)
            HistoryMutationReceiptStore.save(
                HistoryMutationReceipt(
                    mutationID: mutation.id,
                    entryID: entry?.id,
                    revision: entry?.revision
                )
            )
            HistoryMutationOutbox.acknowledge(mutation.id)
        }
    }

    private func consumeAckIfNeeded() {
        guard let ack = FlowSessionBridge.latestAck(),
              let result = FlowSessionBridge.latestResult(),
              ack.sessionId == result.sessionId,
              ack.utteranceId == result.utteranceId,
              ack.commandSeq == result.commandSeq,
              ack.revision == nil
                || result.revision == nil
                || ack.revision == result.revision else {
            return
        }
        FlowSessionBridge.clearResult()
        // Ack clears the terminal result; republish ready immediately so the
        // keyboard does not linger on awaitingDelivery / starting between the
        // 500 ms poll and the next heartbeat.
        refreshHostReady()
    }

    private func hasUnacknowledgedTerminalResult() -> Bool {
        guard let result = FlowSessionBridge.latestResult(),
              result.status == .final
                || result.status == .error
                || result.status == .aborted
                || result.status == .timeout else {
            return false
        }
        guard let ack = FlowSessionBridge.latestAck() else { return true }
        return ack.sessionId != result.sessionId
            || ack.utteranceId != result.utteranceId
            || ack.commandSeq != result.commandSeq
    }

    private var hostUtteranceState: FlowHostUtteranceState {
        if let startingUtteranceId {
            return .starting(startingUtteranceId)
        }
        if isUtteranceRecording, let currentUtteranceId {
            return .recording(currentUtteranceId)
        }
        if isUtteranceProcessing, let currentUtteranceId {
            return .processing(currentUtteranceId)
        }
        return .idle
    }

    private func storeRejectedStart(
        _ command: FlowCommand,
        message: String,
        status: FlowResult.Status
    ) {
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: command.sessionId,
                utteranceId: command.utteranceId,
                commandSeq: command.commandSeq,
                status: status,
                text: message,
                errorKind: .audioUnavailable,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                utteranceMode: command.utteranceMode
            )
        )
        traceState(
            "startRecording.rejected",
            extra: "status=\(status.rawValue) utterance=\(command.utteranceId.uuidString.prefix(8))"
        )
    }

    private func handleFlowCommand(_ command: FlowCommand) {
        switch FlowCommandGatekeeper.decide(
            commandSessionId: command.sessionId,
            commandSeq: command.commandSeq,
            activeSessionId: activeSessionId,
            lastHandledCommandSeq: lastHandledCommandSeq
        ) {
        case .rejectWrongSession:
            traceIgnoredCommand(
                reason: "staleSession",
                command: command,
                detail: "commandSession=\(command.sessionId)"
            )
            return
        case .rejectStaleSeq:
            traceIgnoredCommand(
                reason: "seqNotIncreasing",
                command: command,
                detail: "last=\(lastHandledCommandSeq)"
            )
            return
        case .accept:
            break
        }
        lastHandledCommandSeq = command.commandSeq
        lastIgnoredCommandSignature = ""

        FlowDiagnostics.log(
            "command \(command.action.rawValue) seq=\(command.commandSeq) "
                + "utterance=\(command.utteranceId) "
                + "mode=\(command.resolvedUtteranceMode.rawValue) "
                + "editSourceChars=\(command.editSourceText?.count ?? 0)"
        )

        switch command.action {
        case .startRecording:
            guard command.resolvedUtteranceMode != .unsupportedLegacy else {
                storeRejectedStart(
                    command,
                    message: AppL10n.string("flow.error.recognitionInterrupted"),
                    status: .error
                )
                traceState(
                    "startRecording.rejected",
                    extra: "reason=unsupportedLegacyMode"
                )
                return
            }
            let startDecision = FlowStartTransactionPolicy.decide(
                incomingUtteranceID: command.utteranceId,
                deadlineAt: command.startDeadlineAt,
                hostState: hostUtteranceState
            )
            switch startDecision {
            case .idempotent:
                traceState(
                    "startRecording.idempotent",
                    extra: "utterance=\(command.utteranceId.uuidString.prefix(8))"
                )
                refreshHostReady()
                return
            case .rejectBusy:
                storeRejectedStart(
                    command,
                    message: AppL10n.string("flow.error.recognitionInterrupted"),
                    status: .error
                )
                return
            case .rejectExpired:
                storeRejectedStart(
                    command,
                    message: AppL10n.string("flow.coldStart.error.audioTimeout"),
                    status: .timeout
                )
                return
            case .accept:
                break
            }
            guard prepareUtteranceIdentity(
                utteranceId: command.utteranceId,
                commandSeq: command.commandSeq
            ) else { return }
            let deadlineAt = command.startDeadlineAt
                ?? Date().timeIntervalSince1970 + FlowSessionKeys.utteranceStartBudget
            startingUtteranceId = command.utteranceId
            startTransactionDeadlineAt = deadlineAt
            FlowSessionBridge.writeStartTransaction(
                FlowStartTransaction(
                    sessionID: command.sessionId,
                    utteranceID: command.utteranceId,
                    deadlineAt: deadlineAt,
                    phase: .starting
                )
            )
            currentUtteranceMode = command.resolvedUtteranceMode
            if currentUtteranceMode == .editLastInput {
                let source = command.editSourceText?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                pendingEditSourceText = source?.isEmpty == false ? source : nil
                pendingSourceHistoryEntryID = command.sourceHistoryEntryID
                pendingSourceHistoryEntryRevision = command.sourceHistoryEntryRevision
            } else {
                pendingEditSourceText = nil
                pendingSourceHistoryEntryID = nil
                pendingSourceHistoryEntryRevision = nil
            }
            guard let startUtteranceId = currentUtteranceId else { return }
            let startToken = FlowUtteranceStartToken(
                generation: utteranceGeneration,
                utteranceId: startUtteranceId
            )
            Task { @MainActor [weak self] in
                await self?.handleStartRecordingCommand(
                    utteranceId: command.utteranceId,
                    commandSeq: command.commandSeq,
                    startToken: startToken,
                    deadlineAt: deadlineAt
                )
            }
        case .stopRecording:
            guard currentUtteranceId == command.utteranceId else { return }
            pendingFieldContext = command.fieldContext
            pendingProcessingDeadlineAt = command.processingDeadlineAt
                ?? (currentUtteranceMode == .editLastInput
                    ? Date().timeIntervalSince1970
                        + FlowSessionKeys.editLastInputHostProcessingBudget
                    : nil)
            FlowDiagnostics.log(
                "field context received before/after=" +
                "\(command.fieldContext?.precedingText?.count ?? 0)/" +
                "\(command.fieldContext?.followingText?.count ?? 0)"
            )
            if isUtteranceRecording {
                endUtterance()
            } else if !isUtteranceProcessing {
                // A very short press can place start+stop in the journal before
                // the async capture-start task gets a MainActor turn.
                pendingStopUtteranceId = command.utteranceId
                debug("stop command queued until capture start")
            }
        case .abort:
            guard currentUtteranceId == command.utteranceId else { return }
            abortUtterance()
        case .prewarm:
            // No utterance identity — warm SpeechAnalyzer / cloud prep only.
            scheduleASRWarmup()
            FlowDiagnostics.log("prewarm ASR requested seq=\(command.commandSeq)")
        case .primeAudio:
            beginAudioPrime(command)
        case .cancelPrimeAudio:
            cancelAudioPrime(command)
        }
    }

    private func beginAudioPrime(_ command: FlowCommand) {
        guard startingUtteranceId == nil,
              !isUtteranceRecording,
              !isUtteranceProcessing,
              !hasUnacknowledgedTerminalResult() else {
            return
        }
        startAudioPrime(id: command.utteranceId, origin: "micTouch")
    }

    private func startAudioPrime(id: UUID, origin: String) {
        if audioPrimeTask != nil || capture.engineHasRecentAudio(maxAge: 2) {
            audioPrimeID = id
            audioPrimeCancellationRequested = false
            return
        }
        audioPrimeID = id
        audioPrimeCancellationRequested = false
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.startCaptureForPiPUtteranceIfNeeded()
        }
        audioPrimeTask = task
        Task { @MainActor [weak self] in
            let started = await task.value
            guard let self else { return }
            guard self.audioPrimeID == id else {
                if self.audioPrimeCancellationRequested,
                   self.startingUtteranceId == nil,
                   !self.isUtteranceRecording,
                   !self.isUtteranceProcessing,
                   self.capture.running {
                    self.capture.stop(releaseSession: false)
                    _ = await self.pipController.reassertKeepAliveAudioSession()
                }
                self.audioPrimeTask = nil
                self.audioPrimeCancellationRequested = false
                self.refreshHostReady()
                return
            }
            self.audioPrimeTask = nil
            if self.audioPrimeCancellationRequested,
               self.startingUtteranceId == nil,
               !self.isUtteranceRecording,
               !self.isUtteranceProcessing {
                self.audioPrimeID = nil
                self.audioPrimeCancellationRequested = false
                if self.capture.running {
                    self.capture.stop(releaseSession: false)
                    _ = await self.pipController.reassertKeepAliveAudioSession()
                }
                self.refreshHostReady()
                return
            }
            self.refreshHostReady()
            FlowDiagnostics.log(
                "audio prime completed started=\(started ? 1 : 0) "
                    + "origin=\(origin) utterance=\(id.uuidString.prefix(8))"
            )
        }
    }

    private func cancelAudioPrime(_ command: FlowCommand) {
        guard audioPrimeID == command.utteranceId,
              startingUtteranceId == nil,
              !isUtteranceRecording,
              !isUtteranceProcessing else {
            return
        }
        audioPrimeCancellationRequested = true
        // `capture.start()` is not cancellation-safe. Never stop it mid-start;
        // the completion waiter performs cleanup unless a real utterance adopts
        // this same single-flight task first.
        guard audioPrimeTask == nil else { return }
        audioPrimeID = nil
        audioPrimeCancellationRequested = false
        capture.stop(releaseSession: false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.pipController.reassertKeepAliveAudioSession()
            self.refreshHostReady()
        }
    }

    private func storeCurrentPartial(
        _ text: String,
        generation: UInt64,
        utteranceId: UUID?
    ) {
        guard utteranceGeneration == generation,
              currentUtteranceId == utteranceId,
              let activeSessionId,
              let currentUtteranceId,
              !terminalUtteranceIds.contains(currentUtteranceId) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: activeSessionId,
                utteranceId: currentUtteranceId,
                commandSeq: currentCommandSeq,
                status: .partial,
                text: trimmed,
                rawText: trimmed,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                utteranceMode: currentUtteranceMode
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
                warning: warning,
                rawText: trimmed,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                utteranceMode: currentUtteranceMode
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
                errorKind: kind,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                utteranceMode: currentUtteranceMode
            )
        )
    }

    private func handleStartRecordingCommand(
        utteranceId: UUID?,
        commandSeq: Int64,
        startToken: FlowUtteranceStartToken,
        deadlineAt: TimeInterval
    ) async {
        guard !Task.isCancelled,
              canContinueStart(startToken),
              Date().timeIntervalSince1970 < deadlineAt else {
            failStartIfCurrent(startToken)
            return
        }
        refreshHostReady()
        // Keep the utterance gate closed until the route is stable and the
        // tap has produced a real frame. The rolling three-second preroll
        // preserves speech spoken during this short readiness window.
        guard await ensureCaptureStartedForUtterance() else {
            guard !Task.isCancelled, canContinueStart(startToken) else { return }
            failUtterance(
                message: AppL10n.string("flow.coldStart.error.audioTimeout"),
                kind: .audioUnavailable
            )
            return
        }
        guard !Task.isCancelled, canContinueStart(startToken) else {
            releaseOrphanedCaptureIfNeeded()
            return
        }
        guard Date().timeIntervalSince1970 < deadlineAt else {
            failStartIfCurrent(startToken)
            return
        }
        let micReady: Bool
        if capture.engineHasRecentAudio(maxAge: 2) {
            micReady = true
        } else {
            let firstBudget = min(
                4,
                max(0, deadlineAt - Date().timeIntervalSince1970)
            )
            var flowing = await capture.awaitAudioFlowing(
                timeout: firstBudget
            )
            let remaining = deadlineAt - Date().timeIntervalSince1970
            if !flowing, remaining > 1 {
                // First cold capture after PiP arm often proves audio late — one rebuild.
                debug("PiP audio proof timeout — one capture rebuild before failing")
                capture.stop(releaseSession: false)
                _ = await startCaptureForPiPUtteranceIfNeeded()
                flowing = await capture.awaitAudioFlowing(
                    timeout: min(2, max(0, deadlineAt - Date().timeIntervalSince1970))
                )
            }
            micReady = flowing && Date().timeIntervalSince1970 < deadlineAt
        }
        guard !Task.isCancelled, canContinueStart(startToken) else {
            releaseOrphanedCaptureIfNeeded()
            return
        }
        if !micReady {
            failUtterance(
                message: AppL10n.string("flow.coldStart.error.audioTimeout"),
                kind: .audioUnavailable
            )
            return
        }
        beginUtterance(
            utteranceId: utteranceId,
            commandSeq: commandSeq,
            requireRecentAudio: false
        )
        if pendingStopUtteranceId == currentUtteranceId {
            pendingStopUtteranceId = nil
            endUtterance()
        }
    }

    private func failStartIfCurrent(_ token: FlowUtteranceStartToken) {
        guard canContinueStart(token) else { return }
        failUtterance(
            message: AppL10n.string("flow.coldStart.error.audioTimeout"),
            kind: .audioUnavailable
        )
    }

    private func ensureCaptureStartedForUtterance() async -> Bool {
        audioPrimeCancellationRequested = false
        audioPrimeID = nil
        if let task = audioPrimeTask {
            let started = await task.value
            audioPrimeTask = nil
            if started || capture.engineHasRecentAudio(maxAge: 2) {
                return true
            }
        }
        return await startCaptureForPiPUtteranceIfNeeded()
    }

    /// Start capture for a PiP utterance without blocking on the first frame.
    /// Cold first start after relaunch often needs one rebuild (VPIO / -66635).
    private func startCaptureForPiPUtteranceIfNeeded() async -> Bool {
        if capture.engineHasRecentAudio(maxAge: 2) {
            return true
        }
        do {
            try await capture.start()
            if capture.engineIsLive || capture.engineHasRecentAudio(maxAge: 2) {
                return true
            }
            debug("PiP utterance capture soft-dead after start — one rebuild retry")
            capture.stop(releaseSession: false)
            try? await Task.sleep(nanoseconds: 120_000_000)
            try await capture.start()
            // Do not accept `running && !engineLive` — that is the silent-mic failure mode.
            return capture.engineIsLive || capture.engineHasRecentAudio(maxAge: 2)
        } catch {
            debug("PiP utterance capture start failed: \(error.localizedDescription) — retry once")
            capture.stop(releaseSession: false)
            try? await Task.sleep(nanoseconds: 150_000_000)
            do {
                try await capture.start()
                return capture.engineIsLive || capture.engineHasRecentAudio(maxAge: 2)
            } catch {
                debug("PiP utterance capture retry failed: \(error.localizedDescription)")
                return false
            }
        }
    }

    private func releaseCaptureAfterPiPUtteranceIfNeeded() {
        guard capture.running else { return }
        guard !isUtteranceRecording, !isUtteranceProcessing else { return }
        capture.stop(releaseSession: false)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.pipController.reassertKeepAliveAudioSession()
            self.refreshHostReady()
        }
        pipController.updateWaveformLevels([])
    }

    private func releaseOrphanedCaptureIfNeeded() {
        guard currentUtteranceId == nil,
              !isUtteranceRecording,
              !isUtteranceProcessing else { return }
        traceState("capture.start.discarded", extra: "reason=staleUtterance")
        releaseCaptureAfterPiPUtteranceIfNeeded()
    }

    private func canContinueStart(_ token: FlowUtteranceStartToken) -> Bool {
        FlowUtteranceLifecyclePolicy.canContinueStart(
            token: token,
            currentGeneration: utteranceGeneration,
            currentUtteranceId: currentUtteranceId,
            terminalUtteranceIds: terminalUtteranceIds
        )
    }

    private func beginUtterance(
        utteranceId: UUID? = nil,
        commandSeq: Int64 = 0,
        requireRecentAudio: Bool = true
    ) {
        if let utteranceId, terminalUtteranceIds.contains(utteranceId) {
            traceState(
                "beginUtterance.ignored",
                extra: "reason=terminalId utterance=\(utteranceId.uuidString.prefix(8))"
            )
            return
        }
        if requireRecentAudio {
            guard capture.engineHasRecentAudio(maxAge: 2) else {
                traceState("beginUtterance.blocked", extra: "reason=audioNotRecent")
                failUtterance(
                    message: AppL10n.string("flow.error.audioUnavailable"),
                    kind: .audioUnavailable
                )
                return
            }
        } else {
            // PiP cold path: capture was just started; open the gate so the
            // first tap frames enter the ASR stream instead of preroll only.
            guard capture.running || capture.engineIsLive else {
                traceState("beginUtterance.blocked", extra: "reason=captureNotRunning")
                failUtterance(
                    message: AppL10n.string("flow.error.audioUnavailable"),
                    kind: .audioUnavailable
                )
                return
            }
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

        if currentUtteranceId != utteranceId || currentUtteranceId == nil {
            guard prepareUtteranceIdentity(
                utteranceId: utteranceId,
                commandSeq: commandSeq
            ) else { return }
        }
        let generation = utteranceGeneration
        let taskUtteranceId = currentUtteranceId
        currentCommandSeq = commandSeq
        currentPartial = ""
        lastFinal = ""
        lastFinalWithPauseMarks = ""
        bestPartialSnapshot = ""
        utterancePCMSamples = []
        chunkWarnings = []
        asrCompletedGeneration = nil
        asrFailureMessage = nil

        let localeId = store.localeId
        FlowSessionBridge.setTranscriptionLanguage(localeId)
        FlowSessionBridge.clearPendingTranscription()

        let locale = SpeechLocaleResolver.resolve(localeId)
        let stream = capture.beginUtterance()
        let useStreaming =
            store.engineMode == "cloud"
            && CloudASRModelCatalog.supportsTrueStreamingASR(for: store.asrProviderId)
        let pipeline: ChunkedUtterancePipeline?
        if useStreaming {
            chunkedPipeline = nil
            pipeline = nil
        } else {
            let created = ChunkedUtterancePipeline(asr: asr, locale: locale)
            chunkedPipeline = created
            pipeline = created
        }

        isUtteranceRecording = true
        startingUtteranceId = nil
        startTransactionDeadlineAt = nil
        if let activeSessionId, let currentUtteranceId {
            FlowSessionBridge.writeStartTransaction(
                FlowStartTransaction(
                    sessionID: activeSessionId,
                    utteranceID: currentUtteranceId,
                    deadlineAt: Date().timeIntervalSince1970,
                    phase: .recording
                )
            )
        }
        utteranceRecordingStartedAt = Date()
        startUtteranceSafetyTimer()
        refreshHostReady()
        FlowDiagnostics.log(
            "beginUtterance engine=\(store.engineMode) " +
            "asrType=\(type(of: asr)) streaming=\(useStreaming) " +
            "localCustomLM=\(store.localASRCustomLanguageModelEnabled) " +
            "max=\(Int(FlowSessionKeys.maxUtteranceDuration))s"
        )

        let cloudASRForStreaming = useStreaming ? (asr as? CloudASRService) : nil

        asrTask = Task.detached(priority: .userInitiated) { [weak manager = self] in
            let outcome: ChunkedUtterancePipelineOutcome
            if let cloud = cloudASRForStreaming {
                outcome = await cloud.transcribeUtteranceStreaming(stream: stream, locale: locale) { partial in
                    Task { @MainActor in
                        guard let manager else { return }
                        guard manager.utteranceGeneration == generation,
                              manager.currentUtteranceId == taskUtteranceId else { return }
                        manager.currentPartial = partial
                        manager.storeCurrentPartial(
                            partial,
                            generation: generation,
                            utteranceId: taskUtteranceId
                        )
                    }
                }
            } else if let pipeline {
                outcome = await pipeline.transcribe(stream: stream) { partial in
                    Task { @MainActor in
                        guard let manager else { return }
                        guard manager.utteranceGeneration == generation,
                              manager.currentUtteranceId == taskUtteranceId else { return }
                        manager.currentPartial = partial
                        manager.storeCurrentPartial(
                            partial,
                            generation: generation,
                            utteranceId: taskUtteranceId
                        )
                    }
                }
            } else {
                outcome = .failure(SharedL10n.string("error.asr.noSpeech"))
            }
            // Re-bind `manager` inside the `@MainActor` block so the
            // weak reference is captured under the right isolation. Swift
            // 6 strict concurrency otherwise complains about a
            // task-isolated reference escaping into a main-actor closure.
            await MainActor.run { [weak manager] in
                guard let manager else { return }
                guard manager.utteranceGeneration == generation,
                      manager.currentUtteranceId == taskUtteranceId else {
                    return
                }
                manager.asrCompletedGeneration = generation
                FlowDiagnostics.log(
                    "asr finished streaming=\(useStreaming) partialLen=\(manager.currentPartial.count) " +
                    "finalPending=\(manager.lastFinal.isEmpty)"
                )
                switch outcome {
                case .success(let success):
                    FlowTrace.transcript(
                        "asr.outcome",
                        success.text,
                        "engine=\(manager.store.engineMode) streaming=\(useStreaming ? 1 : 0) "
                            + "warnings=\(success.chunkWarnings.count)"
                    )
                    manager.lastFinal = success.text
                    manager.lastFinalWithPauseMarks = success.textWithPauseMarks
                    manager.chunkWarnings = success.chunkWarnings
                    manager.currentPartial = ""
                case .failure(let message):
                    manager.asrFailureMessage = message
                    manager.debug("asr error: \(message)")
                    FlowTrace.warn(
                        "asr.outcome.failed",
                        "engine=\(manager.store.engineMode) streaming=\(useStreaming ? 1 : 0) "
                            + "partialLen=\(manager.currentPartial.count) "
                            + "bestPartialLen=\(manager.bestPartialSnapshot.count) error=\(message)"
                    )
                    // Prefer any non-empty partial over a hard no-speech failure.
                    // finishProcessing used to clear bestPartialSnapshot and race
                    // finalize into an empty transcript even when ASR had text.
                    let recovery = [
                        manager.currentPartial,
                        manager.bestPartialSnapshot
                    ]
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first(where: { !$0.isEmpty })
                    if let recovery {
                        manager.lastFinal = recovery
                        manager.debug("asr error recovered via partial len=\(recovery.count)")
                    } else if manager.isUtteranceRecording {
                        manager.failUtterance(message: message, kind: .asrFailed)
                    }
                case .cancelled:
                    break
                }
            }
        }

        debug("utterance recording started")
    }

    @discardableResult
    private func prepareUtteranceIdentity(
        utteranceId: UUID?,
        commandSeq: Int64
    ) -> Bool {
        let resolved = utteranceId ?? UUID()
        guard !terminalUtteranceIds.contains(resolved) else {
            traceState(
                "utteranceIdentity.rejected",
                extra: "reason=terminalId utterance=\(resolved.uuidString.prefix(8))"
            )
            return false
        }
        guard currentUtteranceId != resolved else {
            currentCommandSeq = commandSeq
            return true
        }
        utteranceGeneration &+= 1
        currentUtteranceId = resolved
        currentCommandSeq = commandSeq
        return true
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
        FlowSessionBridge.clearStartTransaction()
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
        refreshHostReady()

        // Snapshot pipelined partial before drain — fallback if the final chunk ASR drops tail text.
        bestPartialSnapshot = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)

        // Do NOT cancel `asrTask` or `asr` — drain trailing PCM, then finalize.

        // Capture ids now: a cancelled finalize must still clear *this*
        // utterance's processing gate even if currentUtteranceId was cleared
        // by a racing fail/abort path.
        let drainingSessionId = activeSessionId
        let drainingUtteranceId = currentUtteranceId
        let drainingCommandSeq = currentCommandSeq
        let drainingGeneration = utteranceGeneration
        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let drainReport = await self.capture.endUtteranceAndDrain()
            FlowDiagnostics.logDrain(drainReport)
            self.utterancePCMSamples = self.capture.consumeUtteranceSamples()
            FlowTrace.pipeline(
                "utterance.pcmCollected",
                "samples=\(self.utterancePCMSamples.count) "
                    + "seconds=\(FlowTrace.seconds(samples: self.utterancePCMSamples.count)) "
                    + "rms=\(FlowTrace.rms(self.utterancePCMSamples)) "
                    + "capture[\(self.capture.frameReport().summary)]"
            )
            self.capture.stop(releaseSession: false)
            _ = await self.pipController.reassertKeepAliveAudioSession()
            self.pipController.updateWaveformLevels([])
            await self.finalizeUtterance(
                sessionId: drainingSessionId,
                utteranceId: drainingUtteranceId,
                commandSeq: drainingCommandSeq,
                generation: drainingGeneration
            )
        }
        debug("utterance stopped, draining tail")
    }

    private func abortUtterance() {
        let utteranceId = currentUtteranceId
        if claimTerminal(utteranceId: utteranceId) {
            storeCurrentError(
                AppL10n.string("flow.error.recognitionInterrupted"),
                kind: .recognitionInterrupted,
                status: .aborted
            )
        }
        isUtteranceRecording = false
        isUtteranceProcessing = false
        startingUtteranceId = nil
        startTransactionDeadlineAt = nil
        FlowSessionBridge.clearStartTransaction()
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
        releaseCaptureAfterPiPUtteranceIfNeeded()
        currentPartial = ""
        lastFinal = ""
        lastFinalWithPauseMarks = ""
        bestPartialSnapshot = ""
        utterancePCMSamples = []
        chunkWarnings = []
        pendingFieldContext = nil
        clearPendingInstructionState()
        utteranceGeneration &+= 1
        currentUtteranceId = nil
        currentCommandSeq = 0
        refreshHostReady()
        debug("utterance aborted")
    }

    private func failUtterance(
        message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .asrFailed
    ) {
        guard claimTerminal(utteranceId: currentUtteranceId) else { return }
        isUtteranceRecording = false
        isUtteranceProcessing = false
        startingUtteranceId = nil
        startTransactionDeadlineAt = nil
        FlowSessionBridge.clearStartTransaction()
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
        releaseCaptureAfterPiPUtteranceIfNeeded()
        currentPartial = ""
        lastFinal = ""
        lastFinalWithPauseMarks = ""
        bestPartialSnapshot = ""
        utterancePCMSamples = []
        chunkWarnings = []
        storeCurrentError(message, kind: kind)
        pendingFieldContext = nil
        clearPendingInstructionState()
        utteranceGeneration &+= 1
        currentUtteranceId = nil
        currentCommandSeq = 0
        refreshHostReady()
        debug("utterance failed: \(message)")
    }

    private func finishProcessing(
        withError message: String,
        kind: FlowSessionKeys.TranscriptionErrorKind = .asrFailed
    ) {
        guard claimTerminal(utteranceId: currentUtteranceId) else { return }
        isUtteranceProcessing = false
        startingUtteranceId = nil
        startTransactionDeadlineAt = nil
        FlowSessionBridge.clearStartTransaction()
        utteranceRecordingStartedAt = nil
        utteranceSafetyTask?.cancel()
        utteranceSafetyTask = nil
        finalizeTask?.cancel()
        finalizeTask = nil
        chunkedPipeline = nil
        capture.cancelUtterance()
        releaseCaptureAfterPiPUtteranceIfNeeded()
        currentPartial = ""
        lastFinal = ""
        lastFinalWithPauseMarks = ""
        bestPartialSnapshot = ""
        utterancePCMSamples = []
        chunkWarnings = []
        storeCurrentError(message, kind: kind)
        pendingFieldContext = nil
        clearPendingInstructionState()
        utteranceGeneration &+= 1
        currentUtteranceId = nil
        currentCommandSeq = 0
        refreshHostReady()
        debug("utterance processing failed: \(message)")
    }

    private func claimTerminal(utteranceId: UUID?) -> Bool {
        guard let utteranceId, !terminalUtteranceIds.contains(utteranceId) else {
            return false
        }
        terminalUtteranceIds.insert(utteranceId)
        return true
    }

    private func clearPendingInstructionState() {
        pendingEditSourceText = nil
        pendingSourceHistoryEntryID = nil
        pendingSourceHistoryEntryRevision = nil
        pendingProcessingDeadlineAt = nil
        currentUtteranceMode = .dictation
    }

    private func finalizeUtterance(
        sessionId finalizeSessionId: UUID?,
        utteranceId finalizeUtteranceId: UUID?,
        commandSeq finalizeCommandSeq: Int64,
        generation finalizeGeneration: UInt64
    ) async {
        let pipelineStarted = Date()
        let fieldContext = pendingFieldContext
        let utteranceMode = currentUtteranceMode
        let editSourceText = pendingEditSourceText
        let sourceHistoryEntryID = pendingSourceHistoryEntryID
        let sourceHistoryEntryRevision = pendingSourceHistoryEntryRevision
        let processingDeadlineAt = pendingProcessingDeadlineAt
        // ALWAYS clear the processing gate for this utterance. The previous
        // guard required currentUtteranceId to still match; a racing
        // fail/abort/cancel path could nil the id (or leave processing stuck)
        // and then skip refreshHostReady — keyboard stayed white forever
        // while host logs still said "utterance finalized".
        defer {
            pendingFieldContext = nil
            pendingEditSourceText = nil
            pendingSourceHistoryEntryID = nil
            pendingSourceHistoryEntryRevision = nil
            pendingProcessingDeadlineAt = nil
            if currentUtteranceMode == utteranceMode {
                currentUtteranceMode = .dictation
            }
            completeFinalizeCleanup(
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId
            )
        }

        let asrWait = asrWaitTimeout()
        FlowDiagnostics.log(
            "finalize start asrWait=\(Int(asrWait))s engine=\(store.engineMode)"
        )

        let normalASRDeadline = Date().addingTimeInterval(asrWait)
        let asrDeadline = processingDeadlineAt.map {
            min(normalASRDeadline, Date(timeIntervalSince1970: $0))
        } ?? normalASRDeadline
        while Date() < asrDeadline {
            if !lastFinal.isEmpty { break }
            if asrCompletedGeneration == finalizeGeneration { break }
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
        FlowTrace.transcript(
            "asr.beforeGuard",
            lastFinal,
            "stage=stitchedFinal engine=\(store.engineMode) "
                + "elapsed=\(String(format: "%.2f", asrElapsed))s"
        )
        FlowTrace.transcript("asr.bestPartial", bestPartialSnapshot, "stage=partialSnapshot")

        var text = UtteranceTranscriptGuard.resolve(
            stitchedFinal: lastFinal,
            partialSnapshot: bestPartialSnapshot
        )
        if text.isEmpty {
            text = currentPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let wantsBatchFallback = UtteranceBatchFallbackPolicy.shouldRunBatchFallback(
            stitchedFinal: lastFinal,
            partialSnapshot: bestPartialSnapshot
        )
        FlowTrace.pipeline(
            "batchFallback.decision",
            "wanted=\(wantsBatchFallback ? 1 : 0) pcmSamples=\(utterancePCMSamples.count) "
                + "pcmRms=\(FlowTrace.rms(utterancePCMSamples)) "
                + "stitchedLen=\(lastFinal.count) partialLen=\(bestPartialSnapshot.count) "
                + "resolvedLen=\(text.count)"
        )
        let hasBatchFallbackBudget = processingDeadlineAt.map {
            Date().timeIntervalSince1970 + FlowSessionKeys.batchASRFallbackTimeout < $0
        } ?? true
        if wantsBatchFallback,
           hasBatchFallbackBudget,
           !utterancePCMSamples.isEmpty {
            text = await runBatchASRFallback(currentText: text)
        }
        let textForPolish = text == lastFinal && !lastFinalWithPauseMarks.isEmpty
            ? lastFinalWithPauseMarks
            : text
        utterancePCMSamples = []
        guard !text.isEmpty else {
            let wasCancelled = (asrTask?.isCancelled == true || Task.isCancelled)
            let key = wasCancelled
                ? "flow.error.recognitionInterrupted"
                : "flow.error.noSpeech"
            let kind: FlowSessionKeys.TranscriptionErrorKind =
                asrFailureMessage == nil
                ? (wasCancelled ? .recognitionInterrupted : .noSpeech)
                : .asrFailed
            FlowDiagnostics.log("finalize failed: empty transcript after \(String(format: "%.1f", asrElapsed))s")
            FlowTrace.warn(
                "finalize.emptyTranscript",
                "engine=\(store.engineMode) elapsed=\(String(format: "%.2f", asrElapsed))s "
                    + "kind=\(kind.rawValue) asrCancelled=\(asrTask?.isCancelled == true ? 1 : 0) "
                    + "capture[\(capture.frameReport().summary)]"
            )
            utteranceRecordingStartedAt = nil
            guard claimTerminal(utteranceId: finalizeUtteranceId) else { return }
            storeFinalizedError(
                asrFailureMessage ?? AppL10n.string(key),
                kind: kind,
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId,
                commandSeq: finalizeCommandSeq
            )
            return
        }

        storeRawCandidate(
            text,
            sessionId: finalizeSessionId,
            utteranceId: finalizeUtteranceId,
            commandSeq: finalizeCommandSeq
        )
        let recordingDuration = consumeRecordingDuration()
        if utteranceMode == .editLastInput {
            EditUsageMetricsStore.recordInstructionDuration(recordingDuration)
        }

        let engineMode = store.engineMode
        let chunkNote = Self.chunkWarningMessage(chunkWarnings)
        // Re-read App Group at finalize so chip-side translation changes
        // from the keyboard extension are visible before polish/translate.
        let pipelineStore = AppGroupStore()
        let polishContext = PolishContext(
            appContext: pipelineStore.detectedAppContext?.context ?? .unknown,
            precedingText: fieldContext?.precedingText,
            followingText: fieldContext?.followingText,
            fieldHints: fieldContext.map(FieldHints.init(from:)),
            maxPrecedingChars: 600,
            maxFollowingChars: 200
        )

        var delivered = text
        let polishStarted = Date()
        let isEditLastInput = utteranceMode == .editLastInput
        let isInstructionMode = isEditLastInput
        let polishMode: PolishingService.PolishMode = isInstructionMode
            ? .polish
            : pipelineStore.polishModeForPipeline
        let instructionPrompt: (system: String, user: String)? = {
            if isEditLastInput,
               let source = editSourceText,
               !source.isEmpty {
                let input = EditLastInputPromptComposer.Input(
                    sourceText: source,
                    spokenInstruction: textForPolish
                )
                return (
                    EditLastInputPromptComposer.systemPrompt(),
                    EditLastInputPromptComposer.userMessage(input)
                )
            }
            return nil
        }()

        if isInstructionMode, instructionPrompt == nil {
            FlowDiagnostics.log("instruction edit missing source — failing closed")
            guard claimTerminal(utteranceId: finalizeUtteranceId) else { return }
            storeFinalizedError(
                AppL10n.string("flow.error.editLastInputFailed"),
                kind: .generic,
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId,
                commandSeq: finalizeCommandSeq
            )
            return
        }

        let modeLabel = isEditLastInput
            ? "editLastInput"
            : Self.polishModeLogLabel(polishMode)
        FlowDiagnostics.log(
            "finalize LLM mode=\(modeLabel) translationTarget=\(pipelineStore.translationTargetLocaleId)"
        )
        FlowTrace.transcript(
            "polish.input",
            textForPolish,
            "mode=\(modeLabel) engine=\(engineMode) "
                + "provider=\(pipelineStore.polishProviderIdOverride ?? "default") "
                + "recordedSeconds=\(String(format: "%.2f", recordingDuration))"
        )
        do {
            // If the finalize task was cancelled (cold-start churn / abort),
            // skip the LLM round-trip and deliver the raw transcript so the
            // keyboard is not left waiting on a result that never arrives.
            // Edit mode must never insert the instruction ASR.
            if Task.isCancelled {
                throw CancellationError()
            }
            let outcome = try await Self.polishWithHostTimeout(
                polisher: polisher,
                text: instructionPrompt?.user ?? textForPolish,
                mode: polishMode,
                systemPrompt: instructionPrompt?.system,
                providerIdOverride: pipelineStore.polishProviderIdOverride,
                context: isInstructionMode ? nil : polishContext,
                timeoutLimit: processingDeadlineAt.map {
                    max(0.1, $0 - Date().timeIntervalSince1970)
                }
            )
            let polished: String
            if isEditLastInput, let source = editSourceText {
                switch EditOutputValidator.validate(sourceText: source, output: outcome.text) {
                case .success(let validated):
                    polished = validated
                case .failure(let validationError):
                    throw validationError
                }
            } else {
                polished = outcome.text
            }
            delivered = polished
            FlowTrace.transcript(
                "polish.output",
                polished,
                "mode=\(modeLabel) inputLen=\(text.count) "
                    + "changed=\(polished == text ? 0 : 1) "
                    + "elapsed=\(FlowTrace.seconds(since: polishStarted))s"
            )
            guard claimTerminal(utteranceId: finalizeUtteranceId) else { return }
            let historyEntry = isEditLastInput
                ? nil
                : SpeechHistoryStore.shared.recordUtterance(
                    text: delivered,
                    engineMode: engineMode,
                    duration: recordingDuration,
                    wasTranslation: isInstructionMode
                        ? false
                        : pipelineStore.isTranslationEffective
                )
            storeFinalizedResult(
                polished,
                rawText: isInstructionMode ? nil : text,
                warning: Self.combinedWarning(
                    chunkNote,
                    outcome.qualityDegraded
                        ? AppL10n.string("flow.warning.polishDegradedQuality")
                        : nil
                ),
                sessionId: finalizeSessionId,
                utteranceId: finalizeUtteranceId,
                commandSeq: finalizeCommandSeq,
                historyEntryID: isEditLastInput
                    ? sourceHistoryEntryID
                    : historyEntry?.id,
                historyEntryRevision: isEditLastInput
                    ? sourceHistoryEntryRevision
                    : historyEntry?.revision
            )
            FlowDiagnostics.log(
                "polish done in \(String(format: "%.1f", Date().timeIntervalSince(polishStarted)))s " +
                "total=\(String(format: "%.1f", Date().timeIntervalSince(pipelineStarted)))s"
            )
        } catch {
            if isInstructionMode {
                FlowDiagnostics.log(
                    "instruction edit failed after \(String(format: "%.1f", Date().timeIntervalSince(polishStarted)))s: " +
                    "\(error.localizedDescription)"
                )
                FlowTrace.warn(
                    "editLastInput.failed",
                    "elapsed=\(FlowTrace.seconds(since: polishStarted))s "
                        + "cancelled=\(error is CancellationError ? 1 : 0) "
                        + "error=\(error.localizedDescription)"
                )
                guard claimTerminal(utteranceId: finalizeUtteranceId) else { return }
                storeFinalizedError(
                    AppL10n.string("flow.error.editLastInputFailed"),
                    kind: .generic,
                    sessionId: finalizeSessionId,
                    utteranceId: finalizeUtteranceId,
                    commandSeq: finalizeCommandSeq
                )
            } else {
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
                FlowTrace.warn(
                    "polish.failed",
                    "mode=\(Self.polishModeLogLabel(polishMode)) engine=\(engineMode) "
                        + "elapsed=\(FlowTrace.seconds(since: polishStarted))s "
                        + "cancelled=\(error is CancellationError ? 1 : 0) "
                        + "error=\(error.localizedDescription)"
                )
                FlowTrace.transcript(
                    "polish.fallback",
                    fallback.text,
                    "reason=polishFailed rawLen=\(text.count)"
                )
                delivered = fallback.text
                guard claimTerminal(utteranceId: finalizeUtteranceId) else { return }
                let historyEntry = SpeechHistoryStore.shared.recordUtterance(
                    text: delivered,
                    engineMode: engineMode,
                    duration: recordingDuration,
                    wasTranslation: pipelineStore.isTranslationEffective
                )
                storeFinalizedResult(
                    fallback.text,
                    rawText: text,
                    warning: fallback.polishWarning,
                    sessionId: finalizeSessionId,
                    utteranceId: finalizeUtteranceId,
                    commandSeq: finalizeCommandSeq,
                    historyEntryID: historyEntry?.id,
                    historyEntryRevision: historyEntry?.revision
                )
            }
        }

        currentPartial = ""
        lastFinal = ""
        lastFinalWithPauseMarks = ""
        bestPartialSnapshot = ""
        utterancePCMSamples = []
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
        rawText: String? = nil,
        warning: String?,
        sessionId: UUID?,
        utteranceId: UUID?,
        commandSeq: Int64,
        historyEntryID: UUID? = nil,
        historyEntryRevision: Int64? = nil
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
        FlowTrace.transcript(
            "host.delivered",
            trimmed,
            "utterance=\(utteranceId.uuidString.prefix(8)) commandSeq=\(commandSeq) "
                + "warning=\(warning == nil ? 0 : 1)"
        )
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: .final,
                text: trimmed,
                warning: warning,
                rawText: rawText,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                fieldFingerprint: Self.fieldFingerprint(pendingFieldContext),
                utteranceMode: currentUtteranceMode,
                historyEntryID: historyEntryID,
                historyEntryRevision: historyEntryRevision
            )
        )
    }

    private func storeRawCandidate(
        _ text: String,
        sessionId: UUID?,
        utteranceId: UUID?,
        commandSeq: Int64
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let sessionId, let utteranceId else { return }
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: .rawReady,
                text: trimmed,
                rawText: trimmed,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                fieldFingerprint: Self.fieldFingerprint(pendingFieldContext),
                utteranceMode: currentUtteranceMode
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
        FlowTrace.warn(
            "host.deliveredError",
            "kind=\(kind.rawValue) status=\(status.rawValue) "
                + "utterance=\(utteranceId.uuidString.prefix(8)) commandSeq=\(commandSeq) "
                + "message=\(message)"
        )
        FlowSessionBridge.writeResult(
            FlowResult(
                sessionId: sessionId,
                utteranceId: utteranceId,
                commandSeq: commandSeq,
                status: status,
                text: message,
                errorKind: kind,
                hostGeneration: FlowSessionBridge.currentHostGeneration(),
                revision: Self.resultRevision(),
                fieldFingerprint: Self.fieldFingerprint(pendingFieldContext),
                utteranceMode: currentUtteranceMode
            )
        )
    }

    private static var lastResultRevision: Int64 = 0

    private static func resultRevision() -> Int64 {
        let millis = Int64(Date().timeIntervalSince1970 * 1_000)
        lastResultRevision = max(lastResultRevision + 1, millis)
        return lastResultRevision
    }

    private static func fieldFingerprint(_ context: FlowFieldContext?) -> String? {
        context?.deliveryFingerprint
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

    private static func combinedWarning(_ values: String?...) -> String? {
        let present = values.compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return present.isEmpty ? nil : present.joined(separator: "\n")
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

    /// Re-transcribe the full utterance PCM when pipelined chunking likely dropped tail text.
    private func runBatchASRFallback(currentText: String) async -> String {
        let samples = utterancePCMSamples
        guard !samples.isEmpty else {
            FlowTrace.warn("pipeline.batchFallback.noPCM", "currentLen=\(currentText.count)")
            return currentText
        }

        let locale = SpeechLocaleResolver.resolve(store.localeId)
        let stitched = lastFinal.trimmingCharacters(in: .whitespacesAndNewlines)
        let partial = bestPartialSnapshot.trimmingCharacters(in: .whitespacesAndNewlines)

        FlowDiagnostics.log(
            "batch fallback start samples=\(samples.count) stitchedLen=\(stitched.count) partialLen=\(partial.count)"
        )

        let asrService = asr
        let result = await HardTimeout.value(
            seconds: FlowSessionKeys.batchASRFallbackTimeout
        ) { [asrService] in
            await asrService.transcribeChunk(samples: samples, locale: locale)
        } onTimeout: {
            .cancelled
        }

        switch result {
        case .success(let batchText):
            let trimmedBatch = batchText.trimmingCharacters(in: .whitespacesAndNewlines)
            FlowTrace.transcript(
                "asr.batchFallback",
                trimmedBatch,
                "samples=\(samples.count) seconds=\(FlowTrace.seconds(samples: samples.count)) "
                    + "rms=\(FlowTrace.rms(samples)) currentLen=\(currentText.count)"
            )
            guard !trimmedBatch.isEmpty else { return currentText }
            let resolved = UtteranceBatchFallbackPolicy.preferredTranscript(
                batch: trimmedBatch,
                stitchedFinal: stitched,
                partialSnapshot: partial,
                current: currentText
            )
            FlowPipelineDiagnostics.logBatchFallback(
                sampleCount: samples.count,
                stitchedLength: stitched.count,
                partialLength: partial.count,
                batchLength: trimmedBatch.count
            )
            return resolved
        case .failure(let message):
            FlowDiagnostics.log("batch fallback failed: \(message)")
            FlowTrace.warn(
                "asr.batchFallback.failed",
                "samples=\(samples.count) rms=\(FlowTrace.rms(samples)) error=\(message)"
            )
            return currentText
        case .cancelled:
            FlowTrace.asr("batchFallback.cancelled", "samples=\(samples.count)")
            return currentText
        }
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

    /// Host-level polish cap — does not wait for a cancelled LLM task to unwind.
    private static func polishWithHostTimeout(
        polisher: PolishingService,
        text: String,
        mode: PolishingService.PolishMode,
        systemPrompt: String? = nil,
        providerIdOverride: String?,
        context: PolishContext?,
        timeoutLimit: TimeInterval? = nil
    ) async throws -> PolishingService.PolishOutcome {
        let scaled = FlowSessionKeys.polishTimeout(forCharacterCount: text.count)
        let timeout = timeoutLimit.map { min(scaled, $0) } ?? scaled
        return try await HardTimeout.run(seconds: timeout) {
            try await polisher.polishWithOutcome(
                text,
                mode: mode,
                systemPrompt: systemPrompt,
                providerIdOverride: providerIdOverride,
                context: context
            )
        }
    }

    // MARK: - Level publishing (main thread only)

    private func startLevelPublishing() {
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive else { break }
                guard self.isUtteranceRecording || self.capture.engineIsLive else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                let levels = self.capture.currentAudioLevels()
                self.pipController.updateWaveformLevels(levels)
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
                guard let self else { break }
                if self.isActive,
                   !self.capture.engineIsLive,
                   (self.isUtteranceRecording || self.isUtteranceProcessing) {
                    await self.reactivateCaptureIfNeeded()
                }
                FlowSessionBridge.writeHeartbeat()
                self.refreshHostReady()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.isActive else { break }
            }
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
