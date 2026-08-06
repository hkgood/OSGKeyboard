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
        isPendingFlowStart || isFlowRecording || isAwaitingFlowResult
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
    func ensurePiPReadyOnKeyboardOpen() {
        guard FlowHandoffPolicy.allowsProactiveHostAutoLaunch,
              FlowSessionPolicy.keepAliveMode() == .pictureInPicture,
              state.hasCompletedOnboarding,
              hasFullAccess(),
              AppGroup.isAvailable,
              !isPendingFlowStart,
              !isFlowRecording,
              !isAwaitingFlowResult else { return }

        FlowSessionBridge.reloadFromDisk()
        if FlowSessionBridge.isHostReady() { return }

        if let reason = FlowSessionBridge.readySnapshot()?.reason,
           reason == .recording || reason == .processing || reason == .awaitingDelivery {
            return
        }

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
        // ack lag must not flash yellow「正在启动画中画».
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
            state.phase = .recording
            if state.lastTranscript.isEmpty {
                state.lastTranscript = ""
            }
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
        switch state.phase {
        case .recording:
            pressEnded()
        case .idle, .denied, .error:
            pressBegan()
        case .requestingPermissions, .processing:
            break
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
            recordWhenHostReady = recordWhenReady
            coldStartDebouncer.reset()
            startHostReadyWaitIfNeeded()
            traceState(
                "pressBegan.waitForHostReady",
                extra: recordWhenReady ? "recordWhenReady=1" : "recordWhenReady=0"
            )
        case .openHostColdStart:
            detectAndStoreAppContext()
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
    }

    // MARK: - Private

    private func nextCommandSeq() -> Int64 {
        let millis = Int64(Date().timeIntervalSince1970 * 1_000)
        currentCommandSeq = max(currentCommandSeq + 1, millis)
        return currentCommandSeq
    }

    private func writeCommand(_ action: FlowCommand.Action) {
        guard let activeSessionId, let currentUtteranceId else { return }
        let command = FlowCommand(
            sessionId: activeSessionId,
            utteranceId: currentUtteranceId,
            commandSeq: nextCommandSeq(),
            action: action,
            localeId: state.localeId,
            fieldContext: action == .stopRecording ? fieldContextProvider() : nil
        )
        FlowSessionBridge.writeCommand(command)
        debug(
            "command \(action.rawValue) seq=\(command.commandSeq) " +
            "utterance=\(currentUtteranceId.uuidString) contextChars=" +
            "\(command.fieldContext?.precedingText?.count ?? 0)/" +
            "\(command.fieldContext?.followingText?.count ?? 0)"
        )
        // Start of one traceable utterance: everything the host logs afterwards
        // belongs to this `utterance=` id until the matching keyboard.insert.
        FlowTrace.keyboard(
            "command.\(action.rawValue)",
            "seq=\(command.commandSeq) utterance=\(currentUtteranceId.uuidString.prefix(8)) "
                + "locale=\(state.localeId) engine=\(state.engineMode) "
                + "hostReady=\(FlowSessionBridge.isHostReady() ? 1 : 0)"
        )
    }

    private func consumePendingFlowDeliveryIfNeeded() {
        if isAwaitingFlowResult {
            if let result = matchingResult(), result.status == .final, let text = result.text, !text.isEmpty {
                isAwaitingFlowResult = false
                stopFlowWatchdog()
                textInserter.handleFlowTranscript(
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
                lastConsumedUtteranceId = result.utteranceId
                lastStoppedUtteranceId = nil
                currentUtteranceId = nil
                FlowTrace.transcript(
                    "keyboard.insert",
                    text,
                    "utterance=\(result.utteranceId.uuidString.prefix(8)) "
                        + "commandSeq=\(result.commandSeq) warning=\(result.warning == nil ? 0 : 1)"
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
                recordWhenHostReady = recordWhenReady
                startHostReadyWaitIfNeeded()
            case .openHostColdStart:
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
                beginFlowStart(recordAfterHandoff: true)
            } else {
                recordWhenHostReady = true
                startHostReadyWaitIfNeeded()
            }
            return
        }
        activeSessionId = sessionId
        currentUtteranceId = UUID()
        FlowSessionBridge.setPendingKeyboardUtteranceId(currentUtteranceId)
        lastStoppedUtteranceId = nil
        writeCommand(.startRecording)
        isFlowRecording = true
        state.lastTranscript = ""
        state.phase = .recording
        recomputeMicVoiceAvailability()
        if let view = wakeLockView() {
            ExtensionScreenWakeLock.acquire(from: view)
        }
        startUtteranceCountdown()
        startFlowLevelWatchdog()
        traceState("startFlowRecording.started")
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
                    self.showManualOpenHint(path: "startflow")
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
