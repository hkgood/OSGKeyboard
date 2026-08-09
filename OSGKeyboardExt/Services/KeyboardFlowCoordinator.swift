// KeyboardFlowCoordinator.swift
// OSGKeyboard · Keyboard Extension
//
// Flow session start, recording, watchdogs, and result delivery handling.

import UIKit
import OSGKeyboardShared

@MainActor
final class KeyboardFlowCoordinator {
    private enum FlowWatchdog {
        static let pollIntervalNs: UInt64 = 200_000_000
        /// Give the user time to manually open the host app when auto-jump fails.
        static let startTimeout: TimeInterval = 30

        static func resultTimeout(engineMode: String) -> TimeInterval {
            FlowSessionKeys.keyboardResultTimeout(engineMode: engineMode)
        }
    }

    private let state: KeyboardState
    private let textInserter: KeyboardTextInserter
    private let hasFullAccess: () -> Bool
    private let wakeLockView: () -> UIView?
    private let openHostApp: (String) -> Void
    private let detectAndStoreAppContext: () -> Void
    private let fieldContextProvider: () -> FlowFieldContext?
    private let scheduleAutoClearError: () -> Void
    private let refreshConfigFromAppGroup: () -> Void

    private var isPendingFlowStart = false
    private var flowStartDeadline: TimeInterval = 0
    private var isFlowRecording = false
    private var flowWatchdogTask: Task<Void, Never>?
    private var utteranceTimerTask: Task<Void, Never>?
    private var hostReadyWaitTask: Task<Void, Never>?
    private var utteranceStartedAt: TimeInterval = 0
    private var wasSessionActive = false
    /// Last wall-clock time the host published a fresh ready contract. Used to
    /// smooth over transient cross-process heartbeat read jitter so a single
    /// stale sample never flashes the mic orange while the session is healthy.
    private var lastHostReadyAt: TimeInterval = 0
    private static let hostReadyGrace: TimeInterval = 4
    /// Once the host has published ready for this session, hold green through
    /// brief inter-utterance ready flaps instead of flashing preparingSession.
    private var sessionProvenReady = false
    private var flowSessionMonitorTask: Task<Void, Never>?
    private var isAwaitingFlowResult = false
    private var activeSessionId: UUID?
    private var currentUtteranceId: UUID?
    /// Utterance whose final result we already inserted (or failed). Prevents
    /// `adoptHostBusyStateIfNeeded` from re-entering `.processing` after a
    /// stale App Group snapshot still says `reason=processing`.
    private var lastConsumedUtteranceId: UUID?
    /// Utterance we just asked the host to stop. Until the host publishes
    /// processing/final state, stale App Group snapshots can still say
    /// `reason=recording`; do not re-adopt that utterance as locally active.
    private var lastStoppedUtteranceId: UUID?
    private var currentCommandSeq: Int64 = 0
    private var lastAvailabilityTraceSignature = ""
    /// When true, `completeFlowStartHandoff` starts recording after the host
    /// publishes ready — set only for an explicit mic press.
    private var recordAfterHandoff = false
    /// When true, `startHostReadyWaitIfNeeded` starts recording once ready
    /// (mic pressed while session was still warming / mid ready-flap).
    private var recordWhenHostReady = false
    /// Ignores single-frame "host dead" samples before allowing a cold-start jump
    /// from non-press recovery paths.
    private var coldStartDebouncer = FlowColdStartDebouncer()
    /// Frozen clipboard material for the in-flight clipboard-command utterance.
    private var clipboardFrozenSnapshot: String?
    /// True while the live utterance is a clipboard-command round.
    private var isClipboardCommandUtterance = false
    /// True while blocked inside `UIPasteboard.string` (system paste alert).
    /// Must preserve extension lifecycle / voice surface across that alert.
    private var isAcquiringClipboardPaste = false
    private var clipboardAcquisitionTask: Task<Void, Never>?
    /// Clipboard start sent; waiting for host `reason=recording` before confirmed capture UI.
    private var clipboardAwaitingHostRecordConfirm = false
    /// Wall time when host confirmed real capture for this clipboard utterance.
    private var clipboardHostRecordConfirmedAt: TimeInterval?
    /// User tapped stop — honor after confirm + minimum recording window.
    private var clipboardStopRequested = false
    private var clipboardDeferredStopTask: Task<Void, Never>?
    private var clipboardFailureHintTask: Task<Void, Never>?
    private var clipboardPreparingWatchdogTask: Task<Void, Never>?
    /// Wall time when we entered clipboard「准备录音…」awaiting host confirm.
    private var clipboardPreparingStartedAt: TimeInterval = 0

    init(
        state: KeyboardState,
        textInserter: KeyboardTextInserter,
        hasFullAccess: @escaping () -> Bool,
        wakeLockView: @escaping () -> UIView?,
        openHostApp: @escaping (String) -> Void,
        detectAndStoreAppContext: @escaping () -> Void,
        fieldContextProvider: @escaping () -> FlowFieldContext?,
        scheduleAutoClearError: @escaping () -> Void,
        refreshConfigFromAppGroup: @escaping () -> Void
    ) {
        self.state = state
        self.textInserter = textInserter
        self.hasFullAccess = hasFullAccess
        self.wakeLockView = wakeLockView
        self.openHostApp = openHostApp
        self.detectAndStoreAppContext = detectAndStoreAppContext
        self.fieldContextProvider = fieldContextProvider
        self.scheduleAutoClearError = scheduleAutoClearError
        self.refreshConfigFromAppGroup = refreshConfigFromAppGroup
    }

    var preservesLifecycleOnDisappear: Bool {
        isPendingFlowStart
            || isFlowRecording
            || isAwaitingFlowResult
            || isClipboardCommandUtterance
            || isAcquiringClipboardPaste
            || ClipboardCommandResume.shouldPreferVoice()
    }

    /// True while a clipboard-command round owns the mic (incl. paste-alert acquire).
    var isClipboardCommandActive: Bool {
        isClipboardCommandUtterance
            || isAcquiringClipboardPaste
            || ClipboardCommandResume.shouldPreferVoice()
    }

    /// Session/transcription changes are pushed in real time by Darwin
    /// notifications (see `KeyboardConfigSync.installDarwinObservers`), so this
    /// loop is only a low-frequency safety net for coalesced/dropped Darwin
    /// signals — hence 3 s rather than 1 Hz to save battery while idle.
    private static let sessionMonitorIntervalNs: UInt64 = 3_000_000_000

    func startSessionMonitor() {
        flowSessionMonitorTask?.cancel()
        flowSessionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshSessionState()
                try? await Task.sleep(nanoseconds: Self.sessionMonitorIntervalNs)
            }
        }
    }

    func stopSessionMonitor() {
        flowSessionMonitorTask?.cancel()
        flowSessionMonitorTask = nil
        stopHostReadyWait()
    }

    /// Ensure the containing app has armed its low-profile PiP even when the
    /// keyboard opens directly into Pinyin/English typing mode. The mic stays
    /// visually ready; if the host contract is missing, one automatic handoff
    /// prepares PiP so the next press does not need another app switch.
    ///
    /// Must **not** re-jump when a session is already alive/warming (common after
    /// the user returns from startflow and taps the Voice tab — height/appear
    /// noise used to call this again while `ready` briefly lagged).
    func ensurePiPReadyOnKeyboardOpen() {
        guard FlowHandoffPolicy.allowsProactiveHostAutoLaunch,
              state.hasCompletedOnboarding,
              hasFullAccess(),
              AppGroup.isAvailable,
              !isPendingFlowStart,
              !isFlowRecording,
              !isAwaitingFlowResult else { return }

        FlowSessionBridge.reloadFromDisk()
        let withinReadyGrace = lastHostReadyAt > 0
            && (Date().timeIntervalSince1970 - lastHostReadyAt) <= Self.hostReadyGrace
        let shouldArm = FlowHandoffPolicy.shouldProactivePiPArm(
            hostReady: FlowSessionBridge.isHostReady(),
            snapshotReason: FlowSessionBridge.readySnapshot()?.reason,
            sessionActive: FlowSessionBridge.isSessionActive(),
            hostReachable: FlowSessionBridge.isHostReachable(),
            hostStale: FlowSessionBridge.isHostStale(),
            withinReadyGrace: withinReadyGrace,
            inCooldown: FlowSessionBridge.isPiPArmInCooldown(),
            heartbeatStaleness: FlowSessionBridge.heartbeatStaleness()
        )
        guard shouldArm else {
            traceState("keyboardOpen.autoArmPiP.skipped", extra: "gate=0")
            return
        }

        FlowSessionBridge.markPiPArmAttempt()
        detectAndStoreAppContext()
        beginFlowStart(recordAfterHandoff: false)
        traceState("keyboardOpen.autoArmPiP")
    }

    func refreshSessionState() {
        FlowSessionBridge.reloadFromDisk()
        refreshConfigFromAppGroup()
        refreshFlowPartialIfNeeded()
        adoptPendingResultIfNeeded()
        consumePendingFlowDeliveryIfNeeded()

        recoverFromDeadHostIfNeeded()

        if FlowSessionBridge.clearIfHostStale() {
            debug("cleared zombie Flow session from App Group")
        }

        // A stale "session ended" hint may linger from an earlier drop. If the
        // host is provably ready again, recover to idle now so the mic can go
        // green immediately instead of waiting out the auto-clear timer.
        if case .error(.flowSessionExpired, _) = state.phase,
           FlowSessionBridge.isHostReady() {
            state.phase = .idle
            state.lastTranscript = ""
        }

        recomputeMicVoiceAvailability()
        refreshClipboardEligibility()
        promoteClipboardRecordingFromSnapshotIfNeeded()
        recoverClipboardPreparingIfHostMovedOn()
        startHostReadyWaitIfNeeded()
        // Proactive host auto-launch is disabled (FlowHandoffPolicy): a single
        // stale ready snapshot after finalize must never open startflow.

        // Only surface "session ended" when the session contract *genuinely*
        // dropped (expired / cleared). A transient host-ready flap — engine
        // hiccup or a stale cross-process read while the session is still
        // valid — must never nuke a healthy ready state into a sticky error,
        // otherwise the error phase forces the mic orange and defeats the
        // ready-wait poll until the auto-clear fires.
        let sessionActive = FlowSessionBridge.isSessionActive()
        if wasSessionActive && !sessionActive && !isFlowRecording && !isPendingFlowStart {
            switch state.phase {
            case .recording, .processing:
                break
            default:
                showFlowSessionExpiredHint()
            }
        }
        wasSessionActive = sessionActive
    }

    private func recomputeMicVoiceAvailability() {
        FlowSessionBridge.reloadFromDisk()
        let readySnapshot = FlowSessionBridge.readySnapshot()
        activeSessionId = readySnapshot?.sessionId ?? activeSessionId

        // If the host is mid-utterance but this extension process lost local
        // ownership (jetsam / recreate after app switch), re-adopt it so we
        // show red/white instead of a fake orange "starting" state.
        adoptHostBusyStateIfNeeded(snapshot: readySnapshot)

        let hostReadyRaw = readySnapshot?.ready == true && FlowSessionBridge.isHostReady()
        let sessionActive = FlowSessionBridge.isSessionActive()
        let now = Date().timeIntervalSince1970
        if hostReadyRaw {
            lastHostReadyAt = now
            sessionProvenReady = true
        }
        if !sessionActive {
            sessionProvenReady = false
            lastHostReadyAt = 0
        }
        // Grace window: the host was ready very recently, so treat a momentary
        // stale heartbeat read as "still warming" rather than an outright
        // failure. `isSessionActive` is heartbeat-independent, so it stays true
        // across cross-process read jitter and anchors this smoothing.
        let withinReadyGrace = lastHostReadyAt > 0
            && (now - lastHostReadyAt) <= Self.hostReadyGrace
        // Host busy (recording/processing) is NOT "still starting". Treating
        // it as preparingSession was the orange-stuck bug after cold start:
        // host utt.rec=1 → ready=false → keyboard forever "正在启动…".
        let hostBusy = FlowKeyboardHostWarming.isHostBusy(reason: readySnapshot?.reason)
        // Hold green after the session already proved ready — PiP mic release /
        // ack lag must not flash yellow「正在启动…」.
        let holdReady = FlowKeyboardHostWarming.shouldHoldReady(
            hostReady: hostReadyRaw,
            hostBusy: hostBusy,
            sessionActive: sessionActive,
            sessionProvenReady: sessionProvenReady,
            isPendingFlowStart: isPendingFlowStart,
            snapshotReason: readySnapshot?.reason
        )
        let hostReady = hostReadyRaw || holdReady
        // PiP sessions publish `reason=.starting` while the small window is
        // coming up — treat that as warming so the mic stays orange (wait)
        // instead of jumping into another cold start.
        let hostWarming = FlowKeyboardHostWarming.isHostWarming(
            hostReady: hostReady,
            hostBusy: hostBusy,
            sessionActive: sessionActive,
            hostReachable: FlowSessionBridge.isHostReachable(),
            isPendingFlowStart: isPendingFlowStart,
            withinReadyGrace: withinReadyGrace,
            snapshotReason: readySnapshot?.reason
        )
        state.flowSessionActive = sessionActive
        state.debugPendingFlowStart = isPendingFlowStart
        state.debugFlowRecording = isFlowRecording
        state.debugAwaitingFlowResult = isAwaitingFlowResult
        state.debugHasFullAccess = hasFullAccess()
        state.micVoiceAvailability = MicVoiceAvailabilityResolver.resolve(
            phase: state.phase,
            micDisabled: state.micDisabled,
            hasFullAccess: hasFullAccess(),
            appGroupAvailable: AppGroup.isAvailable,
            hostReady: hostReady,
            isPreparingSession: isPendingFlowStart || hostWarming,
            hasCompletedOnboarding: state.hasCompletedOnboarding
        )
        let signature = [
            "phase=\(String(describing: state.phase))",
            "availability=\(String(describing: state.micVoiceAvailability))",
            hostReady ? "hostReady=1" : "hostReady=0",
            state.flowSessionActive ? "sessionActive=1" : "sessionActive=0",
            isPendingFlowStart ? "pending=1" : "pending=0",
            isFlowRecording ? "recording=1" : "recording=0",
            isAwaitingFlowResult ? "awaiting=1" : "awaiting=0",
            readySnapshot?.reason.rawValue ?? "snapshot=nil"
        ].joined(separator: "|")
        if signature != lastAvailabilityTraceSignature {
            lastAvailabilityTraceSignature = signature
            traceState("availability.update", extra: signature)
        }
    }

    /// Re-attach to a host utterance this keyboard process no longer owns.
    private func adoptHostBusyStateIfNeeded(snapshot: FlowReadySnapshot?) {
        let action = FlowKeyboardAdoptBusyPolicy.decide(
            snapshot: snapshot,
            currentHostGeneration: FlowSessionBridge.currentHostGeneration(),
            isFlowRecording: isFlowRecording,
            isAwaitingFlowResult: isAwaitingFlowResult,
            lastConsumedUtteranceId: lastConsumedUtteranceId,
            lastStoppedUtteranceId: lastStoppedUtteranceId
        )
        switch action {
        case .none:
            return
        case .clearStickyProcessing:
            clearStickyProcessingIfNeeded(hostReady: snapshot?.ready ?? false)
        case .adoptRecording(let sessionId, let busyId):
            // Require the host's utterance id — inventing one makes matchingResult
            // forever miss the real delivery and leaves the mic white forever.
            activeSessionId = sessionId
            currentUtteranceId = busyId
            isPendingFlowStart = false
            flowStartDeadline = 0
            stopHostReadyWait()
            isFlowRecording = true
            // Paste-alert may have destroyed in-memory clipboard flags; sticky
            // snapshot means this busy utterance is still a clipboard round.
            if !isClipboardCommandUtterance,
               ClipboardCommandResume.shouldPreferVoice() {
                if let snap = ClipboardCommandResume.pendingSnapshot(), !snap.isEmpty {
                    clipboardFrozenSnapshot = snap
                }
                isClipboardCommandUtterance = true
            }
            if isClipboardCommandUtterance {
                noteClipboardHostRecordingConfirmed()
            } else {
                state.phase = .recording
                if state.lastTranscript.isEmpty {
                    state.lastTranscript = ""
                }
            }
            publishClipboardUIState()
            if let view = wakeLockView() {
                ExtensionScreenWakeLock.acquire(from: view)
            }
            startUtteranceCountdown()
            startFlowLevelWatchdog()
            traceState("adoptHostBusy.recording", extra: "session=\(sessionId)")
        case .adoptProcessing(let sessionId, let busyId):
            activeSessionId = sessionId
            currentUtteranceId = busyId
            isPendingFlowStart = false
            flowStartDeadline = 0
            isFlowRecording = false
            stopUtteranceCountdown()
            ExtensionScreenWakeLock.release()
            state.phase = .processing
            if state.lastTranscript.isEmpty {
                state.lastTranscript = ExtL10n.string("keyboard.flow.transcribing")
            }
            startFlowResultWatchdog()
            traceState("adoptHostBusy.processing", extra: "session=\(sessionId)")
        }
    }

    /// After insert, a stale `reason=processing` snapshot can bounce the mic
    /// back to white loading. When the host is no longer busy, force idle.
    private func clearStickyProcessingIfNeeded(hostReady: Bool) {
        guard !isAwaitingFlowResult, !isFlowRecording else { return }
        guard case .processing = state.phase else { return }
        state.phase = .idle
        state.lastTranscript = ""
        stopFlowWatchdog()
        currentUtteranceId = nil
        lastStoppedUtteranceId = nil
        traceState(
            "stickyProcessing.cleared",
            extra: hostReady ? "hostReady=1" : "hostReady=0"
        )
    }

    /// Session is live but the ready contract has not landed yet — poll
    /// quickly instead of sticking on "session inactive" orange.
    ///
    /// Cold-start (`osgkeyboard://startflow`) is allowed only when the user
    /// explicitly pressed the mic (`recordWhenHostReady`). An idle open must
    /// never relaunch the host: Flow + ASR warmup then jetsams the keyboard.
    private func startHostReadyWaitIfNeeded() {
        guard !isPendingFlowStart else { return }
        guard FlowSessionBridge.isSessionActive() else {
            stopHostReadyWait()
            if recordWhenHostReady {
                // Session gone while waiting — escalate to a real cold start.
                let shouldRecord = recordWhenHostReady
                recordWhenHostReady = false
                beginFlowStart(recordAfterHandoff: shouldRecord)
            }
            return
        }
        // Host busy ≠ waiting for ready. Do not spin the ready-wait poll.
        if let reason = FlowSessionBridge.readySnapshot()?.reason,
           reason == .recording || reason == .processing {
            stopHostReadyWait()
            recordWhenHostReady = false
            return
        }
        if FlowSessionBridge.isHostReady() {
            stopHostReadyWait()
            finishHostReadyWaitIfNeeded()
            return
        }

        // No mic intent + host already dead → leave cleanup to clearIfHostStale.
        // Starting a wait poll here previously ended in an unprompted startflow.
        if !recordWhenHostReady, isHostTrulyDeadForColdStart() {
            stopHostReadyWait()
            return
        }

        guard hostReadyWaitTask == nil else { return }
        hostReadyWaitTask = Task { @MainActor [weak self] in
            defer { self?.hostReadyWaitTask = nil }
            for _ in 0..<20 {
                guard let self, !Task.isCancelled else { return }
                FlowSessionBridge.reloadFromDisk()
                self.recomputeMicVoiceAvailability()
                if self.state.micVoiceAvailability.isReady {
                    self.finishHostReadyWaitIfNeeded()
                    return
                }
                if self.state.micVoiceAvailability == .recording
                    || self.state.micVoiceAvailability == .processing {
                    self.recordWhenHostReady = false
                    return
                }
                // Host died mid-wait — cold-start only after debounced dead
                // samples AND an explicit mic-driven record intent.
                let dead = self.isHostTrulyDeadForColdStart()
                if self.coldStartDebouncer.observe(hostTrulyDead: dead) {
                    let shouldRecord = self.recordWhenHostReady
                    self.recordWhenHostReady = false
                    self.coldStartDebouncer.reset()
                    if shouldRecord {
                        self.beginFlowStart(recordAfterHandoff: true)
                    } else {
                        self.traceState(
                            "hostReadyWait.deadWithoutIntent",
                            extra: "skipColdStart=1"
                        )
                        self.stopHostReadyWait()
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            // Timed out still not ready — if the user asked to record, cold-start.
            guard let self else { return }
            if self.recordWhenHostReady {
                let shouldRecord = self.recordWhenHostReady
                self.recordWhenHostReady = false
                self.beginFlowStart(recordAfterHandoff: shouldRecord)
            }
        }
    }

    private func isHostTrulyDeadForColdStart() -> Bool {
        FlowHandoffPolicy.shouldOpenHostColdStart(
            sessionActive: FlowSessionBridge.isSessionActive(),
            hostReachable: FlowSessionBridge.isHostReachable(),
            hostStale: FlowSessionBridge.isHostStale(),
            withinReadyGrace: false
        )
    }

    private func finishHostReadyWaitIfNeeded() {
        coldStartDebouncer.reset()
        guard recordWhenHostReady else { return }
        recordWhenHostReady = false
        guard state.micVoiceAvailability.isReady else { return }
        startFlowRecording()
        traceState("hostReadyWait.recordStarted")
    }

    private func stopHostReadyWait() {
        hostReadyWaitTask?.cancel()
        hostReadyWaitTask = nil
    }

    func toggleRecording() {
        // Every non-recording clipboard stage is explicitly cancellable.
        if isClipboardCommandActive, state.phase != .recording {
            cancelClipboardIntent(reason: "userCancel")
            return
        }
        switch state.phase {
        case .recording:
            if isClipboardCommandUtterance {
                requestClipboardStop()
            } else {
                pressEnded()
            }
        case .requestingPermissions:
            // Clipboard preparing: tap cancels/stops once host confirms (+ min window).
            if isClipboardCommandUtterance {
                requestClipboardStop()
            }
        case .idle, .denied, .error:
            pressBegan()
        case .processing:
            break
        }
    }

    /// Long-press creates one persisted intent; acquisition and host warm-up resume automatically.
    func clipboardCommandPressBegan() {
        switch state.phase {
        case .idle, .denied, .error:
            break
        case .processing:
            return
        default:
            return
        }

        // Never overwrite an older recoverable intent with a second UUID.
        if ClipboardCommandResume.currentIntent() != nil {
            restoreClipboardCommandIfNeeded()
            return
        }

        clearClipboardFailureHint()

        guard hasFullAccess() else {
            showClipboardFailure(.noFullAccess)
            return
        }
        if fieldContextProvider()?.isSecureEntry == true {
            showClipboardFailure(.secureField)
            return
        }

        guard let intent = ClipboardCommandResume.beginIntent() else {
            showClipboardFailure(.noFullAccess)
            return
        }
        if state.surface != .voice {
            state.setSurface(.voice)
        }
        currentUtteranceId = intent.id
        isClipboardCommandUtterance = true
        isAcquiringClipboardPaste = true
        state.phase = .requestingPermissions
        state.lastTranscript = ExtL10n.string("keyboard.placeholder.preparingRecording")
        publishClipboardUIState()
        scheduleClipboardAcquisition(intentId: intent.id)
        traceState("clipboard.intent.created", extra: "intent=\(intent.id.uuidString.prefix(8))")
    }

    private func scheduleClipboardAcquisition(intentId: UUID) {
        clipboardAcquisitionTask?.cancel()
        clipboardAcquisitionTask = Task { @MainActor [weak self] in
            // Commit the intent and render cancellable chrome before UIKit may
            // present the system paste-consent sheet.
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.acquireClipboardMaterial(intentId: intentId)
        }
    }

    /// UIKit owns paste consent and may suspend the extension. The persisted
    /// intent makes that interruption resumable even though the content read itself
    /// must stay on the main actor.
    private func acquireClipboardMaterial(intentId: UUID) {
        guard let intent = ClipboardCommandResume.currentIntent(), intent.id == intentId else { return }
        if let snapshot = intent.snapshot, !snapshot.isEmpty {
            clipboardFrozenSnapshot = snapshot
            isAcquiringClipboardPaste = false
            continueClipboardIntent(intentId: intentId)
            return
        }

        isAcquiringClipboardPaste = true
        publishClipboardUIState()
        let sample = ClipboardPasteboardReader.sample()

        // The user may have cancelled while UIKit was returning from consent.
        guard ClipboardCommandResume.currentIntent()?.id == intentId else { return }
        isAcquiringClipboardPaste = false

        guard let raw = sample.text else {
            resetClipboardUtteranceState()
            showClipboardFailure(
                ClipboardPasteboardReader.hasStrings() ? .pasteDenied : .material(.empty)
            )
            refreshClipboardEligibility()
            return
        }

        switch ClipboardMaterialFilter.evaluate(raw) {
        case .rejected(let reason):
            resetClipboardUtteranceState()
            showClipboardFailure(.material(reason))
        case .eligible(let snapshot):
            clipboardFrozenSnapshot = snapshot
            ClipboardCommandResume.storeSnapshot(snapshot)
            continueClipboardIntent(intentId: intentId)
        }
    }

    /// Advance the same intent through host warm-up to one idempotent start.
    private func continueClipboardIntent(intentId: UUID) {
        guard let intent = ClipboardCommandResume.currentIntent(),
              intent.id == intentId,
              let snapshot = intent.snapshot,
              !snapshot.isEmpty else { return }
        clipboardFrozenSnapshot = snapshot
        currentUtteranceId = intentId
        isClipboardCommandUtterance = true
        isAcquiringClipboardPaste = false
        clipboardAwaitingHostRecordConfirm = true
        state.phase = .requestingPermissions
        state.lastTranscript = ExtL10n.string("keyboard.placeholder.preparingRecording")
        publishClipboardUIState()

        recomputeMicVoiceAvailability()
        let hostReadyRaw = FlowSessionBridge.isHostReady()
        let withinReadyGrace = lastHostReadyAt > 0
            && (Date().timeIntervalSince1970 - lastHostReadyAt) <= Self.hostReadyGrace
        // Force-quit leaves sessionActive=true; treat unreachable heartbeat as dead
        // so clipboard can still open startflow (same grace as proactive PiP arm).
        let heartbeatStale = FlowSessionBridge.heartbeatStaleness() ?? .infinity
        let sessionEffectivelyDead = !FlowSessionBridge.isHostReachable()
            && heartbeatStale >= FlowHandoffPolicy.proactiveUnreachableArmGrace
        let sessionActiveForGate = FlowSessionBridge.isSessionActive() && !sessionEffectivelyDead
        let micAction: FlowMicPressAction
        if hostReadyRaw, state.micVoiceAvailability.isReady {
            micAction = .startRecording
        } else {
            micAction = FlowHandoffPolicy.micPressAction(
                availability: hostReadyRaw ? state.micVoiceAvailability : .unavailable(.hostNotReady),
                sessionActive: sessionActiveForGate,
                hostReachable: FlowSessionBridge.isHostReachable(),
                hostStale: FlowSessionBridge.isHostStale() || sessionEffectivelyDead,
                withinReadyGrace: withinReadyGrace
            )
        }
        switch ClipboardPreparingPolicy.hostGateAction(micPressAction: micAction) {
        case .startRecordingNow:
            startFlowRecording()
        case .openHostColdStart:
            detectAndStoreAppContext()
            if !isPendingFlowStart, !FlowSessionBridge.isPiPArmInCooldown() {
                beginFlowStart(recordAfterHandoff: true)
            }
            showClipboardHostWarmupHint()
        case .waitForHost:
            recordWhenHostReady = true
            coldStartDebouncer.reset()
            startHostReadyWaitIfNeeded()
            showClipboardHostWarmupHint()
        case .ignore:
            recordWhenHostReady = true
            startHostReadyWaitIfNeeded()
            showClipboardHostWarmupHint()
        }
        traceState("clipboard.intent.advancing", extra: "intent=\(intentId.uuidString.prefix(8))")
    }

    /// Keep the intent live and let the existing host-ready loop auto-start it.
    private func deferClipboardUntilHostWarm(reason: String) {
        isClipboardCommandUtterance = true
        clipboardAwaitingHostRecordConfirm = true
        recordWhenHostReady = true
        state.phase = .requestingPermissions
        state.lastTranscript = ExtL10n.string("keyboard.placeholder.preparingRecording")
        publishClipboardUIState()
        startHostReadyWaitIfNeeded()
        traceState("clipboard.intent.waitingHost", extra: reason)
    }

    /// Soft progress hint; the mic remains tappable to cancel the intent.
    private func showClipboardHostWarmupHint() {
        state.clipboardFailureHint = ExtL10n.string("keyboard.clipboard.hint.hostStarting")
        clipboardFailureHintTask?.cancel()
        let duration = ClipboardMaterialFilter.failureHintDuration
        clipboardFailureHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.clearClipboardFailureHint()
        }
    }

    /// After paste-alert / cold-start recreation, resume the same persisted intent.
    func restoreClipboardCommandIfNeeded() {
        guard let intent = ClipboardCommandResume.currentIntent() else { return }
        if state.surface != .voice {
            state.setSurface(.voice)
        }

        // Snapshot for the next long-press (cold-start return) — not a live round yet.
        if let snapshot = ClipboardCommandResume.pendingSnapshot(), !snapshot.isEmpty {
            clipboardFrozenSnapshot = snapshot
        }

        let hasIssued = ClipboardCommandResume.hasStartIssued()
        if hasIssued,
           !isClipboardCommandUtterance,
           let issued = ClipboardCommandResume.startIssuedUtteranceId() {
            isClipboardCommandUtterance = true
            currentUtteranceId = issued
            traceState(
                "clipboard.resume.rehydratedLive",
                extra: "utterance=\(issued.uuidString.prefix(8))"
            )
        }

        // Prefer adopting an in-flight host utterance (keeps one wire start).
        FlowSessionBridge.reloadFromDisk()
        if let ready = FlowSessionBridge.readySnapshot(),
           ready.reason == .recording || ready.reason == .processing {
            adoptHostBusyStateIfNeeded(snapshot: ready)
        }

        let preparingPhase: ClipboardPreparingPhase = {
            switch state.phase {
            case .idle: return .idle
            case .denied: return .denied
            case .error: return .error
            case .requestingPermissions: return .requestingPermissions
            case .recording: return .recording
            case .processing: return .processing
            }
        }()

        switch ClipboardPreparingPolicy.restoreAction(
            hasStartIssued: hasIssued,
            phase: preparingPhase
        ) {
        case .awaitExistingStart:
            isClipboardCommandUtterance = true
            clipboardAwaitingHostRecordConfirm = true
            clipboardPreparingStartedAt = Date().timeIntervalSince1970
            state.phase = .requestingPermissions
            state.lastTranscript = ExtL10n.string("keyboard.placeholder.preparingRecording")
            publishClipboardUIState()
            scheduleClipboardPreparingWatchdog()
            ensureClipboardStartCommandWritten()
            recoverClipboardPreparingIfHostMovedOn()
            traceState("clipboard.resume.awaitExistingStart")
        case .resumeIntent:
            currentUtteranceId = intent.id
            isClipboardCommandUtterance = true
            clipboardAwaitingHostRecordConfirm = true
            state.phase = .requestingPermissions
            state.lastTranscript = ExtL10n.string("keyboard.placeholder.preparingRecording")
            publishClipboardUIState()
            if intent.snapshot?.isEmpty == false {
                continueClipboardIntent(intentId: intent.id)
            } else {
                isAcquiringClipboardPaste = true
                scheduleClipboardAcquisition(intentId: intent.id)
            }
            traceState("clipboard.resume.intent", extra: "intent=\(intent.id.uuidString.prefix(8))")
        case .refreshOnly:
            publishClipboardUIState()
            if clipboardAwaitingHostRecordConfirm {
                ensureClipboardStartCommandWritten()
            }
            recoverClipboardPreparingIfHostMovedOn()
        }
    }

    /// Explicit tap-to-stop for an in-flight clipboard-command utterance.
    func requestClipboardStop() {
        guard isClipboardCommandUtterance else { return }
        switch ClipboardPreparingPolicy.stopWhilePreparing(
            awaitingHostConfirm: clipboardAwaitingHostRecordConfirm
        ) {
        case .abortPreparing:
            abortClipboardPreparing(reason: "userCancel", message: nil)
            return
        case .requestStop:
            break
        }
        clipboardStopRequested = true
        if let confirmedAt = clipboardHostRecordConfirmedAt {
            let elapsed = Date().timeIntervalSince1970 - confirmedAt
            let minimum = ClipboardMaterialFilter.minimumRecordingAfterHostConfirm
            if elapsed < minimum {
                scheduleClipboardDeferredStop(after: minimum - elapsed)
                traceState(
                    "clipboard.stop.deferred",
                    extra: "reason=minRecording remaining=\(String(format: "%.2f", minimum - elapsed))"
                )
                return
            }
        }
        pressEnded()
    }

    /// Cancel any non-recording clipboard stage and delete the persisted intent.
    private func cancelClipboardIntent(reason: String) {
        clipboardAcquisitionTask?.cancel()
        clipboardAcquisitionTask = nil
        if isFlowRecording || isAwaitingFlowResult {
            writeCommand(.abort)
            isFlowRecording = false
            isAwaitingFlowResult = false
            stopUtteranceCountdown()
            ExtensionScreenWakeLock.release()
        }
        isPendingFlowStart = false
        recordAfterHandoff = false
        recordWhenHostReady = false
        flowStartDeadline = 0
        stopFlowWatchdog()
        stopHostReadyWait()
        FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
        currentUtteranceId = nil
        resetClipboardUtteranceState()
        state.phase = .idle
        state.lastTranscript = ""
        recomputeMicVoiceAvailability()
        traceState("clipboard.intent.cancelled", extra: reason)
    }

    /// Idle affordance only: metadata `hasStrings`. Never reads pasteboard contents.
    func setClipboardContentReadsEnabled(_ enabled: Bool) {
        // Height-lock gate retained as a refresh hook after presentation; content
        // reads are no longer tied to this flag.
        if enabled {
            refreshClipboardEligibility()
        }
    }

    func refreshClipboardEligibility() {
        let secure = fieldContextProvider()?.isSecureEntry == true
        guard hasFullAccess(), !secure else {
            state.clipboardCommandEligible = false
            publishClipboardUIState()
            return
        }
        // Sticky snapshot (after cold-start) keeps long-press affordance even if
        // the pasteboard was cleared while the user was in the host app.
        let hasStickyMaterial = !(ClipboardCommandResume.pendingSnapshot() ?? "").isEmpty
            || !(clipboardFrozenSnapshot ?? "").isEmpty
        state.clipboardCommandEligible =
            ClipboardPasteboardReader.hasStrings() || hasStickyMaterial
        publishClipboardUIState()
    }

    private func resetClipboardUtteranceState() {
        clipboardAcquisitionTask?.cancel()
        clipboardAcquisitionTask = nil
        clipboardDeferredStopTask?.cancel()
        clipboardDeferredStopTask = nil
        clipboardPreparingWatchdogTask?.cancel()
        clipboardPreparingWatchdogTask = nil
        clipboardPreparingStartedAt = 0
        clipboardFrozenSnapshot = nil
        isClipboardCommandUtterance = false
        isAcquiringClipboardPaste = false
        clipboardAwaitingHostRecordConfirm = false
        clipboardHostRecordConfirmedAt = nil
        clipboardStopRequested = false
        ClipboardCommandResume.clear()
        publishClipboardUIState()
    }

    private func publishClipboardUIState() {
        state.clipboardCommandUtteranceActive =
            isClipboardCommandUtterance || isAcquiringClipboardPaste
        // Blue chrome only after host-confirmed capture — preparing stays grey.
        state.clipboardCommandRecording =
            isClipboardCommandUtterance
            && state.phase == .recording
            && !clipboardAwaitingHostRecordConfirm
    }

    private func showClipboardFailure(_ failure: ClipboardCommandFailure) {
        ClipboardCommandResume.clear()
        isClipboardCommandUtterance = false
        isAcquiringClipboardPaste = false
        clipboardFrozenSnapshot = nil
        publishClipboardUIState()
        state.clipboardFailureHint = ExtL10n.string(failure.localizationKey)
        traceState("clipboard.rejected", extra: failure.localizationKey)
        clipboardFailureHintTask?.cancel()
        let duration = ClipboardMaterialFilter.failureHintDuration
        clipboardFailureHintTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.clearClipboardFailureHint()
        }
    }

    private func clearClipboardFailureHint() {
        clipboardFailureHintTask?.cancel()
        clipboardFailureHintTask = nil
        if state.clipboardFailureHint != nil {
            state.clipboardFailureHint = nil
        }
    }

    /// Promote preparing → recording when host publishes real capture; honor deferred stop.
    private func noteClipboardHostRecordingConfirmed() {
        let now = Date().timeIntervalSince1970
        if clipboardAwaitingHostRecordConfirm || clipboardHostRecordConfirmedAt == nil {
            clipboardAwaitingHostRecordConfirm = false
            clipboardPreparingWatchdogTask?.cancel()
            clipboardPreparingWatchdogTask = nil
            clipboardPreparingStartedAt = 0
            if clipboardHostRecordConfirmedAt == nil {
                clipboardHostRecordConfirmedAt = now
            }
            state.phase = .recording
            if state.lastTranscript == ExtL10n.string("keyboard.placeholder.preparingRecording")
                || state.lastTranscript == ExtL10n.string("keyboard.placeholder.preparing") {
                state.lastTranscript = ""
            }
            publishClipboardUIState()
            KeyboardHapticFeedback.play(role: .action, intensity: state.keyboardHapticIntensity)
            traceState("clipboard.hostRecording.confirmed")
        }
        if clipboardStopRequested {
            let confirmedAt = clipboardHostRecordConfirmedAt ?? now
            let elapsed = now - confirmedAt
            let minimum = ClipboardMaterialFilter.minimumRecordingAfterHostConfirm
            if elapsed >= minimum {
                pressEnded()
            } else {
                scheduleClipboardDeferredStop(after: minimum - elapsed)
            }
        }
    }

    private func scheduleClipboardDeferredStop(after delay: TimeInterval) {
        clipboardDeferredStopTask?.cancel()
        let seconds = max(0.05, delay)
        clipboardDeferredStopTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.isClipboardCommandUtterance, self.clipboardStopRequested else { return }
            guard self.isFlowRecording else { return }
            self.pressEnded()
        }
    }

    private func scheduleClipboardPreparingWatchdog() {
        clipboardPreparingWatchdogTask?.cancel()
        let timeout = ClipboardCommandResume.preparingTimeout
        clipboardPreparingWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            guard self.isClipboardCommandUtterance, self.clipboardAwaitingHostRecordConfirm else { return }
            self.abortClipboardPreparing(
                reason: "watchdog",
                message: ExtL10n.string(ClipboardCommandFailure.prepareFailed.localizationKey)
            )
        }
    }

    /// Leave「准备录音…」without waiting for a host confirm that never arrives.
    private func abortClipboardPreparing(reason: String, message: String?) {
        guard isClipboardCommandUtterance, clipboardAwaitingHostRecordConfirm else { return }
        clipboardPreparingWatchdogTask?.cancel()
        clipboardPreparingWatchdogTask = nil
        clipboardPreparingStartedAt = 0
        clipboardAwaitingHostRecordConfirm = false
        clipboardStopRequested = false
        clipboardDeferredStopTask?.cancel()
        clipboardDeferredStopTask = nil

        if isFlowRecording {
            writeCommand(.abort)
            isFlowRecording = false
            stopUtteranceCountdown()
            ExtensionScreenWakeLock.release()
        }
        stopFlowWatchdog()
        FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
        lastStoppedUtteranceId = currentUtteranceId
        currentUtteranceId = nil

        resetClipboardUtteranceState()
        if let message, !message.isEmpty {
            state.clipboardFailureHint = message
            clipboardFailureHintTask?.cancel()
            let duration = ClipboardMaterialFilter.failureHintDuration
            clipboardFailureHintTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.clearClipboardFailureHint()
            }
            state.phase = .idle
            state.lastTranscript = ""
        } else {
            state.phase = .idle
            state.lastTranscript = ""
        }
        recomputeMicVoiceAvailability()
        traceState("clipboard.preparing.aborted", extra: reason)
    }

    /// If we already sent start and host is recording our utterance, confirm UI.
    private func promoteClipboardRecordingFromSnapshotIfNeeded() {
        guard isClipboardCommandUtterance, clipboardAwaitingHostRecordConfirm else { return }
        guard let snapshot = FlowSessionBridge.readySnapshot(),
              snapshot.reason == .recording,
              let busyId = snapshot.busyUtteranceId,
              busyId == currentUtteranceId else { return }
        noteClipboardHostRecordingConfirmed()
    }

    /// Host finished/failed/took another utterance while UI still shows「准备录音…」.
    private func recoverClipboardPreparingIfHostMovedOn() {
        let hostReason: ClipboardHostBusyReason? = {
            switch FlowSessionBridge.readySnapshot()?.reason {
            case .recording: return .recording
            case .processing: return .processing
            default: return nil
            }
        }()
        let action = ClipboardPreparingPolicy.recoverWhilePreparing(
            awaitingHostConfirm: clipboardAwaitingHostRecordConfirm,
            currentUtteranceId: currentUtteranceId,
            hostBusyUtteranceId: FlowSessionBridge.readySnapshot()?.busyUtteranceId,
            hostReason: hostReason,
            hasTerminalFailureForCurrent: {
                guard let result = matchingResult() else { return false }
                return isTerminalFailure(result)
            }()
        )

        switch action {
        case .none, .wait:
            return
        case .abortForHostFailure:
            if let result = matchingResult(), isTerminalFailure(result) {
                FlowSessionBridge.writeAck(
                    FlowAck(
                        sessionId: result.sessionId,
                        utteranceId: result.utteranceId,
                        commandSeq: result.commandSeq,
                        hostGeneration: result.hostGeneration,
                        revision: result.revision
                    )
                )
                lastConsumedUtteranceId = result.utteranceId
                abortClipboardPreparing(
                    reason: "hostTerminalFailure",
                    message: result.text
                        ?? ExtL10n.string(ClipboardCommandFailure.prepareFailed.localizationKey)
                )
            } else {
                abortClipboardPreparing(
                    reason: "hostTerminalFailure",
                    message: ExtL10n.string(ClipboardCommandFailure.prepareFailed.localizationKey)
                )
            }
        case .confirmRecording:
            noteClipboardHostRecordingConfirmed()
        case .adoptSibling(let busyId):
            currentUtteranceId = busyId
            FlowSessionBridge.setPendingKeyboardUtteranceId(busyId)
            ClipboardCommandResume.markStartIssued(busyId)
            let snapshot = FlowSessionBridge.readySnapshot()
            isFlowRecording = snapshot?.reason == .recording
            if snapshot?.reason == .recording {
                noteClipboardHostRecordingConfirmed()
            } else {
                clipboardAwaitingHostRecordConfirm = false
                clipboardPreparingWatchdogTask?.cancel()
                clipboardPreparingWatchdogTask = nil
                state.phase = .processing
                state.lastTranscript = ExtL10n.string("keyboard.flow.transcribing")
                publishClipboardUIState()
                startFlowResultWatchdog()
            }
            traceState(
                "clipboard.preparing.adoptSibling",
                extra: "busy=\(busyId.uuidString.prefix(8)) reason=\(snapshot?.reason.rawValue ?? "nil")"
            )
        }
    }

    /// After restore / claim: write at most one startRecording for the issued utterance.
    private func ensureClipboardStartCommandWritten() {
        guard isClipboardCommandUtterance else { return }
        // The persisted intent id is the one and only utterance id. `startIssued`
        // is committed only immediately before the wire command is written.
        let issued = ClipboardCommandResume.currentIntent()?.id
        let snapshot = FlowSessionBridge.readySnapshot()
        let hostReason: ClipboardHostBusyReason? = {
            switch snapshot?.reason {
            case .recording: return .recording
            case .processing: return .processing
            default: return nil
            }
        }()
        let action = ClipboardPreparingPolicy.ensureStartAction(
            issuedUtteranceId: issued,
            isFlowRecording: isFlowRecording,
            currentUtteranceId: currentUtteranceId,
            hostBusyUtteranceId: snapshot?.busyUtteranceId,
            hostReason: hostReason,
            hostReadyWithSession: snapshot?.sessionId != nil && FlowSessionBridge.isHostReady()
        )

        switch action {
        case .none:
            return
        case .alreadyInFlight:
            return
        case .adoptBusy(let busyId, let reason):
            currentUtteranceId = busyId
            FlowSessionBridge.setPendingKeyboardUtteranceId(busyId)
            ClipboardCommandResume.markStartIssued(busyId)
            if reason == .recording {
                isFlowRecording = true
                noteClipboardHostRecordingConfirmed()
            }
            return
        case .waitForHost:
            recordWhenHostReady = true
            startHostReadyWaitIfNeeded()
            traceState("clipboard.ensureStart.waitHost")
            return
        case .writeStart(let utteranceId):
            guard let sessionId = snapshot?.sessionId else {
                recordWhenHostReady = true
                startHostReadyWaitIfNeeded()
                return
            }
            activeSessionId = sessionId
            currentUtteranceId = utteranceId
            FlowSessionBridge.setPendingKeyboardUtteranceId(utteranceId)
            lastStoppedUtteranceId = nil
            ClipboardCommandResume.markStartIssued(utteranceId)
            writeCommand(.startRecording)
            isFlowRecording = true
            clipboardAwaitingHostRecordConfirm = true
            if clipboardPreparingStartedAt <= 0 {
                clipboardPreparingStartedAt = Date().timeIntervalSince1970
            }
            clipboardHostRecordConfirmedAt = nil
            state.phase = .requestingPermissions
            state.lastTranscript = ExtL10n.string("keyboard.placeholder.preparingRecording")
            publishClipboardUIState()
            scheduleClipboardPreparingWatchdog()
            if let view = wakeLockView() {
                ExtensionScreenWakeLock.acquire(from: view)
            }
            startUtteranceCountdown()
            startFlowLevelWatchdog()
            recomputeMicVoiceAvailability()
            traceState(
                "clipboard.ensureStart.written",
                extra: "utterance=\(utteranceId.uuidString.prefix(8))"
            )
        }
    }

    func pressBegan() {
        switch state.phase {
        case .idle, .denied, .error:
            break
        default:
            return
        }
        guard !isPendingFlowStart else { return }

        recomputeMicVoiceAvailability()

        switch state.micVoiceAvailability {
        case .unavailable(.onboardingIncomplete):
            promptFinishSetupInApp()
            return
        case .unavailable(.missingAPIKey):
            return
        case .unavailable(.noFullAccess):
            let msg = ExtL10n.string("keyboard.error.fullAccessRequired")
            state.phase = .error(.fullAccessRequired, message: msg)
            scheduleAutoClearError()
            recomputeMicVoiceAvailability()
            return
        case .unavailable(.appGroupUnavailable):
            let msg = ExtL10n.string("keyboard.error.appGroupCommunication")
            state.phase = .error(.appGroupUnavailable, message: msg)
            scheduleAutoClearError()
            recomputeMicVoiceAvailability()
            return
        default:
            break
        }

        let withinReadyGrace = lastHostReadyAt > 0
            && (Date().timeIntervalSince1970 - lastHostReadyAt) <= Self.hostReadyGrace
        let action = FlowHandoffPolicy.micPressAction(
            availability: state.micVoiceAvailability,
            sessionActive: FlowSessionBridge.isSessionActive(),
            hostReachable: FlowSessionBridge.isHostReachable(),
            hostStale: FlowSessionBridge.isHostStale(),
            withinReadyGrace: withinReadyGrace
        )
        switch action {
        case .startRecording:
            detectAndStoreAppContext()
            startFlowRecording()
        case .waitForHostReady(let recordWhenReady):
            detectAndStoreAppContext()
            if isClipboardCommandUtterance {
                deferClipboardUntilHostWarm(reason: "pressBegan.waitHost")
                recordWhenHostReady = true
                startHostReadyWaitIfNeeded()
                showClipboardHostWarmupHint()
                traceState("pressBegan.clipboardAutoResume", extra: "waitHost")
                break
            }
            recordWhenHostReady = recordWhenReady
            coldStartDebouncer.reset()
            startHostReadyWaitIfNeeded()
            traceState(
                "pressBegan.waitForHostReady",
                extra: recordWhenReady ? "recordWhenReady=1" : "recordWhenReady=0"
            )
        case .openHostColdStart:
            detectAndStoreAppContext()
            if isClipboardCommandUtterance {
                deferClipboardUntilHostWarm(reason: "pressBegan.coldStart")
                if !isPendingFlowStart {
                    beginFlowStart(recordAfterHandoff: true)
                }
                showClipboardHostWarmupHint()
                traceState("pressBegan.clipboardAutoResume", extra: "coldStart")
                break
            }
            beginFlowStart(recordAfterHandoff: true)
        case .ignore:
            return
        }
    }

    func pressEnded() {
        if isPendingFlowStart {
            cancelPendingFlowStart()
            return
        }
        guard isFlowRecording else { return }

        clipboardDeferredStopTask?.cancel()
        clipboardDeferredStopTask = nil
        clipboardAwaitingHostRecordConfirm = false
        clipboardStopRequested = false
        isFlowRecording = false
        stopUtteranceCountdown()
        ExtensionScreenWakeLock.release()
        lastStoppedUtteranceId = currentUtteranceId
        writeCommand(.stopRecording)
        debug("pressEnded wrote stop command")
        state.phase = .processing
        state.lastTranscript = ExtL10n.string("keyboard.flow.transcribing")
        startFlowResultWatchdog()
        recomputeMicVoiceAvailability()
        publishClipboardUIState()
    }

    func beginFlowStart(recordAfterHandoff: Bool = false) {
        guard state.hasCompletedOnboarding else {
            promptFinishSetupInApp()
            return
        }
        guard !isPendingFlowStart else {
            traceState("beginFlowStart.ignored", extra: "reason=pendingAlreadyTrue")
            return
        }
        self.recordAfterHandoff = recordAfterHandoff
        recordWhenHostReady = false
        coldStartDebouncer.reset()
        isPendingFlowStart = true
        isFlowRecording = false
        flowStartDeadline = Date().timeIntervalSince1970 + FlowWatchdog.startTimeout
        state.lastTranscript = ""
        recomputeMicVoiceAvailability()
        FlowSessionBridge.markPiPArmAttempt()
        OSGDiag.log(
            "beginFlowStart → openHostApp(startflow) recordAfterHandoff=\(recordAfterHandoff) "
                + "\(OSGDiag.memoryTag())",
            category: "boot"
        )
        openHostApp("startflow")
        startFlowStartWatchdog()
        traceState(
            "beginFlowStart.started",
            extra: recordAfterHandoff ? "recordAfterHandoff=1" : "recordAfterHandoff=0"
        )
    }

    func handleHostAppOpenResult(path: String, success: Bool) {
        traceState("openHostApp.result", extra: "path=\(path) success=\(success)")
        guard !success else { return }

        // The open genuinely failed (iOS blocked it / no Full Access). Don't
        // let the 30s watchdog spin — cancel the pending start immediately and
        // guide the user to open OSGKeyboard manually.
        if path == "startflow", isPendingFlowStart {
            isPendingFlowStart = false
            recordAfterHandoff = false
            flowStartDeadline = 0
            stopFlowWatchdog()
            traceState("openHostApp.failed", extra: "path=startflow cancelPending=1")
            showManualOpenHint(path: "startflow")
            recomputeMicVoiceAvailability()
            return
        }

        showManualOpenHint(path: path)
    }

    func cancelPipelineUnlessAwaitingResult() {
        guard !isAwaitingFlowResult else { return }
        // A clipboard intent is explicitly persisted to survive pressure,
        // paste-consent suspension, and extension recreation.
        guard !isClipboardCommandActive else { return }
        if isFlowRecording || isPendingFlowStart {
            if isFlowRecording {
                writeCommand(.abort)
                ExtensionScreenWakeLock.release()
            }
            currentUtteranceId = nil
            lastStoppedUtteranceId = nil
            isFlowRecording = false
            isPendingFlowStart = false
            recordAfterHandoff = false
            stopUtteranceCountdown()
            stopFlowWatchdog()
            state.level = 0
            recomputeMicVoiceAvailability()
        }
        resetClipboardUtteranceState()
    }

    // MARK: - Private

    private func nextCommandSeq() -> Int64 {
        let millis = Int64(Date().timeIntervalSince1970 * 1_000)
        currentCommandSeq = max(currentCommandSeq + 1, millis)
        return currentCommandSeq
    }

    private func writeCommand(_ action: FlowCommand.Action) {
        guard let activeSessionId, let currentUtteranceId else { return }
        let mode: FlowUtteranceMode? = isClipboardCommandUtterance ? .clipboardCommand : nil
        let snapshot: String? = {
            guard isClipboardCommandUtterance, action == .startRecording else { return nil }
            return clipboardFrozenSnapshot
        }()
        let command = FlowCommand(
            sessionId: activeSessionId,
            utteranceId: currentUtteranceId,
            commandSeq: nextCommandSeq(),
            action: action,
            localeId: state.localeId,
            fieldContext: action == .stopRecording ? fieldContextProvider() : nil,
            utteranceMode: mode,
            clipboardSnapshot: snapshot,
            previousOutput: nil
        )
        FlowSessionBridge.writeCommand(command)
        debug(
            "command \(action.rawValue) seq=\(command.commandSeq) " +
            "utterance=\(currentUtteranceId.uuidString) mode=\(mode?.rawValue ?? "dictation") contextChars=" +
            "\(command.fieldContext?.precedingText?.count ?? 0)/" +
            "\(command.fieldContext?.followingText?.count ?? 0)"
        )
        // Start of one traceable utterance: everything the host logs afterwards
        // belongs to this `utterance=` id until the matching keyboard.insert.
        FlowTrace.keyboard(
            "command.\(action.rawValue)",
            "seq=\(command.commandSeq) utterance=\(currentUtteranceId.uuidString.prefix(8)) "
                + "locale=\(state.localeId) engine=\(state.engineMode) "
                + "hostReady=\(FlowSessionBridge.isHostReady() ? 1 : 0) "
                + "mode=\(mode?.rawValue ?? "dictation")"
        )
    }

    private func consumePendingFlowDeliveryIfNeeded() {
        if isAwaitingFlowResult {
            if let result = matchingResult(), result.status == .final, let text = result.text, !text.isEmpty {
                isAwaitingFlowResult = false
                stopFlowWatchdog()
                let wasClipboard = result.resolvedUtteranceMode == .clipboardCommand
                    || isClipboardCommandUtterance
                // Each clipboard round is independent — always append/insert, never replace.
                textInserter.handleFlowTranscript(
                    TranscriptionDelivery(text: text, polishWarning: result.warning)
                )
                resetClipboardUtteranceState()
                FlowSessionBridge.writeAck(
                    FlowAck(
                        sessionId: result.sessionId,
                        utteranceId: result.utteranceId,
                        commandSeq: result.commandSeq,
                        hostGeneration: result.hostGeneration,
                        revision: result.revision
                    )
                )
                FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
                lastConsumedUtteranceId = result.utteranceId
                lastStoppedUtteranceId = nil
                currentUtteranceId = nil
                FlowTrace.transcript(
                    "keyboard.insert",
                    text,
                    "utterance=\(result.utteranceId.uuidString.prefix(8)) "
                        + "commandSeq=\(result.commandSeq) warning=\(result.warning == nil ? 0 : 1) "
                        + "clipboard=\(wasClipboard ? 1 : 0)"
                )
                recomputeMicVoiceAvailability()
                return
            }
            if let result = matchingResult(), isTerminalFailure(result) {
                FlowTrace.warn(
                    "keyboard.resultFailed",
                    "status=\(result.status.rawValue) "
                        + "kind=\(result.errorKind?.rawValue ?? "none") "
                        + "utterance=\(result.utteranceId.uuidString.prefix(8)) "
                        + "message=\(result.text ?? "nil")"
                )
                isAwaitingFlowResult = false
                stopFlowWatchdog()
                resetClipboardUtteranceState()
                FlowSessionBridge.writeAck(
                    FlowAck(
                        sessionId: result.sessionId,
                        utteranceId: result.utteranceId,
                        commandSeq: result.commandSeq,
                        hostGeneration: result.hostGeneration,
                        revision: result.revision
                    )
                )
                FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
                lastConsumedUtteranceId = result.utteranceId
                lastStoppedUtteranceId = nil
                currentUtteranceId = nil
                let error = FlowTranscriptionError(
                    message: result.text ?? ExtL10n.string("keyboard.flow.resultTimeout"),
                    kind: result.errorKind ?? .generic
                )
                state.phase = .error(
                    .fromFlowTranscription(error),
                    message: error.message
                )
                scheduleAutoClearError()
                recomputeMicVoiceAvailability()
                return
            }
        }

        if isPendingFlowStart, FlowSessionBridge.isHostReady() {
            completeFlowStartHandoff()
        }
    }

    private func adoptPendingResultIfNeeded() {
        guard !isAwaitingFlowResult, currentUtteranceId == nil,
              let pendingId = FlowSessionBridge.pendingKeyboardUtteranceId(),
              let result = FlowSessionBridge.latestResult(),
              result.utteranceId == pendingId,
              result.status == .final || isTerminalFailure(result) else {
            return
        }
        let currentField = fieldContextProvider()
        if let expected = result.fieldFingerprint,
           let current = currentField?.deliveryFingerprint,
           expected != current {
            if let text = result.text,
               currentField?.precedingText?.hasSuffix(text) == true {
                FlowSessionBridge.writeAck(
                    FlowAck(
                        sessionId: result.sessionId,
                        utteranceId: result.utteranceId,
                        commandSeq: result.commandSeq,
                        hostGeneration: result.hostGeneration,
                        revision: result.revision
                    )
                )
                FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
                lastConsumedUtteranceId = result.utteranceId
                traceState(
                    "pendingResult.acknowledged",
                    extra: "reason=textAlreadyPresent"
                )
                return
            }
            traceState(
                "pendingResult.deferred",
                extra: "reason=fieldFingerprintMismatch"
            )
            return
        }
        activeSessionId = result.sessionId
        currentUtteranceId = result.utteranceId
        isAwaitingFlowResult = true
        state.phase = .processing
        traceState(
            "pendingResult.adopted",
            extra: "utterance=\(pendingId.uuidString.prefix(8))"
        )
    }

    private func matchingResult() -> FlowResult? {
        FlowKeyboardResultMatcher.matchingResult(
            latest: FlowSessionBridge.latestResult(),
            activeSessionId: activeSessionId,
            currentUtteranceId: currentUtteranceId,
            currentHostGeneration: FlowSessionBridge.currentHostGeneration()
        )
    }

    private func isTerminalFailure(_ result: FlowResult) -> Bool {
        FlowKeyboardResultMatcher.isTerminalFailure(result)
    }

    /// When the host process died mid-utterance, abort local recording / waiting
    /// so the user is not stuck until the long result watchdog fires.
    private func recoverFromDeadHostIfNeeded() {
        guard FlowSessionBridge.isHostStale() else { return }

        if isFlowRecording {
            isFlowRecording = false
            stopUtteranceCountdown()
            ExtensionScreenWakeLock.release()
            writeCommand(.abort)
            currentUtteranceId = nil
            lastStoppedUtteranceId = nil
            stopFlowWatchdog()
            state.level = 0
            state.phase = .idle
            state.lastTranscript = ""
            recomputeMicVoiceAvailability()
            debug("aborted recording — host heartbeat zombie")
            return
        }

        if isAwaitingFlowResult {
            failHostDisconnected()
        }
    }

    private func failHostDisconnected() {
        if deliverRawFallbackIfAvailable(reason: "hostDisconnected") {
            return
        }
        traceState("hostDisconnected.fail")
        isAwaitingFlowResult = false
        isFlowRecording = false
        isPendingFlowStart = false
        recordAfterHandoff = false
        stopUtteranceCountdown()
        ExtensionScreenWakeLock.release()
        writeCommand(.abort)
        currentUtteranceId = nil
        lastStoppedUtteranceId = nil
        stopFlowWatchdog()
        state.level = 0
        let message = ExtL10n.string("keyboard.flow.hostDisconnected")
        state.phase = .error(.flowSessionExpired, message: message)
        scheduleAutoClearError()
        recomputeMicVoiceAvailability()
        debug("host disconnected while awaiting Flow result")
    }

    @discardableResult
    private func deliverRawFallbackIfAvailable(reason: String) -> Bool {
        FlowSessionBridge.reloadFromDisk()
        guard let result = matchingResult(),
              result.allowsRawFallback,
              result.status == .partial
                || result.status == .rawReady
                || (result.status == .final && result.rawText != nil),
              let raw = (result.rawText ?? result.text)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return false
        }
        textInserter.handleFlowTranscript(
            TranscriptionDelivery(text: raw, polishWarning: nil)
        )
        FlowSessionBridge.writeAck(
            FlowAck(
                sessionId: result.sessionId,
                utteranceId: result.utteranceId,
                commandSeq: result.commandSeq,
                hostGeneration: result.hostGeneration,
                revision: nil
            )
        )
        FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
        lastConsumedUtteranceId = result.utteranceId
        lastStoppedUtteranceId = nil
        currentUtteranceId = nil
        isAwaitingFlowResult = false
        isFlowRecording = false
        stopFlowWatchdog()
        state.level = 0
        state.phase = .idle
        state.lastTranscript = ""
        recomputeMicVoiceAvailability()
        FlowTrace.transcript(
            "keyboard.insert",
            raw,
            "via=rawFallback reason=\(reason) utterance=\(result.utteranceId.uuidString.prefix(8))"
        )
        return true
    }

    private func showFlowSessionExpiredHint() {
        let message = ExtL10n.string("keyboard.flow.sessionExpired")
        state.phase = .error(.flowSessionExpired, message: message)
        scheduleAutoClearError()
        recomputeMicVoiceAvailability()
    }

    private func showManualOpenHint(path: String) {
        let msg: String
        if !hasFullAccess() {
            msg = ExtL10n.string("keyboard.error.fullAccessForJump")
        } else if path == "settings" {
            msg = ExtL10n.string("keyboard.error.manualOpenSettings")
        } else if path == "startflow" {
            msg = ExtL10n.string("keyboard.error.manualOpenForFlow")
        } else {
            msg = ExtL10n.string("keyboard.error.manualOpenSettings")
        }
        state.phase = .error(.manualOpenRequired, message: msg)
        scheduleAutoClearError()
        recomputeMicVoiceAvailability()
    }

    /// Scheme C: voice needs host-app setup; typing stays available.
    private func promptFinishSetupInApp() {
        let msg = ExtL10n.string("keyboard.hint.finishSetupInApp")
        state.phase = .error(.manualOpenRequired, message: msg)
        scheduleAutoClearError()
        recomputeMicVoiceAvailability()
        openHostApp("settings")
        traceState("onboarding.incomplete", extra: "action=openHostApp(settings)")
    }

    private func startFlowRecording() {
        recomputeMicVoiceAvailability()
        let withinReadyGrace = lastHostReadyAt > 0
            && (Date().timeIntervalSince1970 - lastHostReadyAt) <= Self.hostReadyGrace
        if !state.micVoiceAvailability.isReady {
            let action = FlowHandoffPolicy.micPressAction(
                availability: state.micVoiceAvailability,
                sessionActive: FlowSessionBridge.isSessionActive(),
                hostReachable: FlowSessionBridge.isHostReachable(),
                hostStale: FlowSessionBridge.isHostStale(),
                withinReadyGrace: withinReadyGrace
            )
            traceState(
                "startFlowRecording.blocked",
                extra: "availability=\(String(describing: state.micVoiceAvailability)) action=\(action)"
            )
            switch action {
            case .waitForHostReady(let recordWhenReady):
                if isClipboardCommandUtterance {
                    deferClipboardUntilHostWarm(reason: "startFlowRecording.waitHost")
                    showClipboardHostWarmupHint()
                    return
                }
                recordWhenHostReady = recordWhenReady
                startHostReadyWaitIfNeeded()
            case .openHostColdStart:
                if isClipboardCommandUtterance {
                    deferClipboardUntilHostWarm(reason: "startFlowRecording.coldStart")
                    if !isPendingFlowStart {
                        beginFlowStart(recordAfterHandoff: true)
                    }
                    showClipboardHostWarmupHint()
                    return
                }
                beginFlowStart(recordAfterHandoff: true)
            case .startRecording, .ignore:
                break
            }
            return
        }
        isPendingFlowStart = false
        flowStartDeadline = 0
        stopFlowWatchdog()

        guard let sessionId = FlowSessionBridge.readySnapshot()?.sessionId else {
            traceState("startFlowRecording.blocked", extra: "reason=missingSessionIdInReadySnapshot")
            // Snapshot lag with a live session → wait; only cold-start if host is dead.
            if FlowHandoffPolicy.shouldOpenHostColdStart(
                sessionActive: FlowSessionBridge.isSessionActive(),
                hostReachable: FlowSessionBridge.isHostReachable(),
                hostStale: FlowSessionBridge.isHostStale(),
                withinReadyGrace: withinReadyGrace
            ) {
                if isClipboardCommandUtterance {
                    deferClipboardUntilHostWarm(reason: "startFlowRecording.missingSession.coldStart")
                    if !isPendingFlowStart {
                        beginFlowStart(recordAfterHandoff: true)
                    }
                    showClipboardHostWarmupHint()
                } else {
                    beginFlowStart(recordAfterHandoff: true)
                }
            } else if isClipboardCommandUtterance {
                deferClipboardUntilHostWarm(reason: "startFlowRecording.missingSession.wait")
                showClipboardHostWarmupHint()
            } else {
                recordWhenHostReady = true
                startHostReadyWaitIfNeeded()
            }
            return
        }
        // Clipboard: never send a second startRecording for the same round
        // (paste-alert restore used to call pressBegan again → stuck「准备录音…」).
        if isClipboardCommandUtterance {
            if isFlowRecording {
                scheduleClipboardPreparingWatchdog()
                recoverClipboardPreparingIfHostMovedOn()
                recomputeMicVoiceAvailability()
                traceState("startFlowRecording.deduped", extra: "reason=alreadyInFlight")
                return
            }
            ensureClipboardStartCommandWritten()
            return
        }

        activeSessionId = sessionId
        currentUtteranceId = UUID()
        FlowSessionBridge.setPendingKeyboardUtteranceId(currentUtteranceId)
        lastStoppedUtteranceId = nil
        writeCommand(.startRecording)
        isFlowRecording = true
        clipboardAwaitingHostRecordConfirm = false
        clipboardHostRecordConfirmedAt = nil
        clipboardStopRequested = false
        state.lastTranscript = ""
        state.phase = .recording
        recomputeMicVoiceAvailability()
        if let view = wakeLockView() {
            ExtensionScreenWakeLock.acquire(from: view)
        }
        startUtteranceCountdown()
        startFlowLevelWatchdog()
        traceState("startFlowRecording.started", extra: "clipboardPreparing=0")
    }

    private func startUtteranceCountdown() {
        utteranceStartedAt = Date().timeIntervalSince1970
        state.utteranceRemainingSeconds = Int(FlowSessionKeys.maxUtteranceDuration)
        utteranceTimerTask?.cancel()
        utteranceTimerTask = Task { @MainActor [weak self] in
            while let self, self.isFlowRecording, !Task.isCancelled {
                let elapsed = Date().timeIntervalSince1970 - self.utteranceStartedAt
                let remaining = max(0, Int(ceil(FlowSessionKeys.maxUtteranceDuration - elapsed)))
                self.state.utteranceRemainingSeconds = remaining
                if remaining <= 0 {
                    self.pressEnded()
                    return
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    private func stopUtteranceCountdown() {
        utteranceTimerTask?.cancel()
        utteranceTimerTask = nil
        state.utteranceRemainingSeconds = Int(FlowSessionKeys.maxUtteranceDuration)
    }

    private func cancelPendingFlowStart() {
        isPendingFlowStart = false
        recordAfterHandoff = false
        recordWhenHostReady = false
        flowStartDeadline = 0
        coldStartDebouncer.reset()
        stopFlowWatchdog()
        stopHostReadyWait()
        state.phase = .idle
        state.lastTranscript = ""
        recomputeMicVoiceAvailability()
        traceState("pendingStart.cancelledByUser")
    }

    private func startFlowStartWatchdog() {
        stopFlowWatchdog()
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isPendingFlowStart {
                self.recomputeMicVoiceAvailability()
                if FlowSessionBridge.isHostReady() {
                    self.completeFlowStartHandoff()
                    return
                }
                let now = Date().timeIntervalSince1970
                if self.flowStartDeadline > 0, now > self.flowStartDeadline {
                    self.isPendingFlowStart = false
                    self.recordAfterHandoff = false
                    self.flowStartDeadline = 0
                    self.traceState("startWatchdog.timeout")
                    if self.isClipboardCommandActive {
                        self.cancelClipboardIntent(reason: "hostWarmTimeout")
                        self.showClipboardFailure(.prepareFailed)
                    } else {
                        self.showManualOpenHint(path: "startflow")
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func completeFlowStartHandoff() {
        let shouldRecord = recordAfterHandoff
        isPendingFlowStart = false
        recordAfterHandoff = false
        flowStartDeadline = 0
        stopFlowWatchdog()
        state.lastTranscript = ""
        refreshSessionState()
        if shouldRecord {
            startFlowRecording()
            traceState("completeFlowStartHandoff.done", extra: "record=1")
        } else {
            recomputeMicVoiceAvailability()
            traceState("completeFlowStartHandoff.done", extra: "record=0 warmOnly")
        }
    }

    private func startFlowLevelWatchdog() {
        stopFlowWatchdog()
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isFlowRecording {
                let levels = FlowSessionBridge.audioLevels()
                if let peak = levels.max(), peak > 0 {
                    self.state.level = Double(peak)
                }
                self.refreshFlowPartialIfNeeded()
                let staleness = FlowSessionBridge.heartbeatStaleness() ?? .infinity
                if staleness > 5 {
                    self.debug("levelWatchdog: host heartbeat stale while recording")
                    self.failHostDisconnected()
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func refreshFlowPartialIfNeeded() {
        guard isFlowRecording || isAwaitingFlowResult else { return }
        switch state.phase {
        case .recording, .processing:
            if let result = matchingResult(),
               result.status == .partial || result.status == .rawReady,
               let partial = result.text,
               !partial.isEmpty {
                state.lastTranscript = partial
            }
        default:
            break
        }
    }

    private func startFlowResultWatchdog() {
        stopFlowWatchdog()
        isAwaitingFlowResult = true
        let startedAt = Date().timeIntervalSince1970
        let resultTimeout = FlowWatchdog.resultTimeout(engineMode: state.engineMode)
        debug("resultWatchdog started timeout=\(Int(resultTimeout))s engine=\(state.engineMode)")
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                FlowSessionBridge.reloadFromDisk()
                if let result = self.matchingResult(), result.status == .final, let text = result.text, !text.isEmpty {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.textInserter.handleFlowTranscript(
                        TranscriptionDelivery(text: text, polishWarning: result.warning)
                    )
                    FlowSessionBridge.writeAck(
                        FlowAck(
                            sessionId: result.sessionId,
                            utteranceId: result.utteranceId,
                            commandSeq: result.commandSeq,
                            hostGeneration: result.hostGeneration,
                            revision: result.revision
                        )
                    )
                    FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
                    self.lastConsumedUtteranceId = result.utteranceId
                    self.lastStoppedUtteranceId = nil
                    self.currentUtteranceId = nil
                    self.debug("resultWatchdog consumed delivery len=\(text.count)")
                    FlowTrace.transcript(
                        "keyboard.insert",
                        text,
                        "via=resultWatchdog utterance=\(result.utteranceId.uuidString.prefix(8)) "
                            + "commandSeq=\(result.commandSeq) "
                            + "waitedSeconds=\(String(format: "%.2f", Date().timeIntervalSince1970 - startedAt))"
                    )
                    return
                }
                if let result = self.matchingResult(), self.isTerminalFailure(result) {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    FlowSessionBridge.writeAck(
                        FlowAck(
                            sessionId: result.sessionId,
                            utteranceId: result.utteranceId,
                            commandSeq: result.commandSeq,
                            hostGeneration: result.hostGeneration,
                            revision: result.revision
                        )
                    )
                    FlowSessionBridge.setPendingKeyboardUtteranceId(nil)
                    self.lastConsumedUtteranceId = result.utteranceId
                    self.lastStoppedUtteranceId = nil
                    self.currentUtteranceId = nil
                    let error = FlowTranscriptionError(
                        message: result.text ?? ExtL10n.string("keyboard.flow.resultTimeout"),
                        kind: result.errorKind ?? .generic
                    )
                    self.debug("resultWatchdog consumed error kind=\(error.kind.rawValue)")
                    FlowTrace.warn(
                        "keyboard.resultFailed",
                        "via=resultWatchdog status=\(result.status.rawValue) "
                            + "kind=\(error.kind.rawValue) "
                            + "utterance=\(result.utteranceId.uuidString.prefix(8)) "
                            + "message=\(error.message)"
                    )
                    self.state.phase = .error(
                        .fromFlowTranscription(error),
                        message: error.message
                    )
                    self.scheduleAutoClearError()
                    self.recomputeMicVoiceAvailability()
                    return
                }
                self.refreshFlowPartialIfNeeded()
                let now = Date().timeIntervalSince1970
                let staleness = FlowSessionBridge.heartbeatStaleness() ?? .infinity
                if self.isFlowRecording, staleness > 5 {
                    self.debug("level/result watchdog: host heartbeat stale while recording")
                    self.failHostDisconnected()
                    return
                }
                if staleness > FlowSessionKeys.heartbeatZombieInterval {
                    self.debug("resultWatchdog: host heartbeat zombie (staleness=\(String(format: "%.1f", staleness))s)")
                    self.failHostDisconnected()
                    return
                }
                if !FlowSessionBridge.isHostReachable(),
                   now - startedAt > FlowSessionKeys.keyboardHostDisconnectFailFast {
                    self.debug("resultWatchdog: host unreachable after \(String(format: "%.1f", now - startedAt))s")
                    self.failHostDisconnected()
                    return
                }
                if now - startedAt > resultTimeout {
                    if self.deliverRawFallbackIfAvailable(reason: "resultTimeout") {
                        return
                    }
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.currentUtteranceId = nil
                    self.lastStoppedUtteranceId = nil
                    self.debug("resultWatchdog TIMEOUT after \(Int(resultTimeout))s — no result from host")
                    let msg = ExtL10n.string("keyboard.flow.resultTimeout")
                    self.state.phase = .error(.flowResultTimeout, message: msg)
                    self.scheduleAutoClearError()
                    self.recomputeMicVoiceAvailability()
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func stopFlowWatchdog() {
        flowWatchdogTask?.cancel()
        flowWatchdogTask = nil
    }

    private func debug(_ message: String) {
        OSGLog.keyboardExt.info("\(message, privacy: .public)")
    }

    private func traceState(_ event: String, extra: String? = nil) {
        let staleness = FlowSessionBridge.heartbeatStaleness().map { String(format: "%.1f", $0) } ?? "nil"
        let sessionId = activeSessionId?.uuidString ?? "nil"
        let utteranceId = currentUtteranceId?.uuidString ?? "nil"
        let summary = [
            "event=\(event)",
            "phase=\(String(describing: state.phase))",
            "availability=\(String(describing: state.micVoiceAvailability))",
            "pending=\(isPendingFlowStart)",
            "recording=\(isFlowRecording)",
            "awaiting=\(isAwaitingFlowResult)",
            "sessionId=\(sessionId)",
            "utteranceId=\(utteranceId)",
            "cmdSeq=\(currentCommandSeq)",
            "sessionActive=\(FlowSessionBridge.isSessionActive())",
            "hostReady=\(FlowSessionBridge.isHostReady())",
            "heartbeatStaleness=\(staleness)"
        ].joined(separator: " ")
        if let extra, !extra.isEmpty {
            debug("[trace] \(summary) \(extra)")
        } else {
            debug("[trace] \(summary)")
        }
    }
}
