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
    private var flowSessionMonitorTask: Task<Void, Never>?
    private var isAwaitingFlowResult = false

    init(
        state: KeyboardState,
        textInserter: KeyboardTextInserter,
        hasFullAccess: @escaping () -> Bool,
        wakeLockView: @escaping () -> UIView?,
        openHostApp: @escaping (String) -> Void,
        detectAndStoreAppContext: @escaping () -> Void,
        scheduleAutoClearError: @escaping () -> Void,
        refreshConfigFromAppGroup: @escaping () -> Void
    ) {
        self.state = state
        self.textInserter = textInserter
        self.hasFullAccess = hasFullAccess
        self.wakeLockView = wakeLockView
        self.openHostApp = openHostApp
        self.detectAndStoreAppContext = detectAndStoreAppContext
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

    func refreshSessionState() {
        FlowSessionBridge.reloadFromDisk()
        refreshConfigFromAppGroup()
        refreshFlowPartialIfNeeded()
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
        let hostReady = FlowSessionBridge.isHostReady()
        let now = Date().timeIntervalSince1970
        if hostReady { lastHostReadyAt = now }
        // Grace window: the host was ready very recently, so treat a momentary
        // stale heartbeat read as "still warming" rather than an outright
        // failure. `isSessionActive` is heartbeat-independent, so it stays true
        // across cross-process read jitter and anchors this smoothing.
        let withinReadyGrace = lastHostReadyAt > 0
            && (now - lastHostReadyAt) <= Self.hostReadyGrace
        let hostWarming = !hostReady
            && FlowSessionBridge.isSessionActive()
            && (FlowSessionBridge.isHostReachable() || isPendingFlowStart || withinReadyGrace)
        state.flowSessionActive = hostReady
        state.micVoiceAvailability = MicVoiceAvailabilityResolver.resolve(
            phase: state.phase,
            micDisabled: state.micDisabled,
            hasFullAccess: hasFullAccess(),
            appGroupAvailable: AppGroup.isAvailable,
            hostReady: hostReady,
            isPreparingSession: isPendingFlowStart || hostWarming
        )
    }

    /// Session is live but the ready contract has not landed yet — poll
    /// quickly instead of sticking on "session inactive" orange.
    private func startHostReadyWaitIfNeeded() {
        guard !isPendingFlowStart else { return }
        guard FlowSessionBridge.isSessionActive() else {
            stopHostReadyWait()
            return
        }
        guard !FlowSessionBridge.isHostReady() else {
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
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
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
        case .ready:
            detectAndStoreAppContext()
            startFlowRecording()
        case .unavailable(.missingAPIKey):
            return
        case .unavailable(.noFullAccess):
            let msg = ExtL10n.string("keyboard.error.fullAccessRequired")
            state.phase = .error(.fullAccessRequired, message: msg)
            scheduleAutoClearError()
            recomputeMicVoiceAvailability()
        case .unavailable(.appGroupUnavailable):
            let msg = ExtL10n.string("keyboard.error.appGroupCommunication")
            state.phase = .error(.appGroupUnavailable, message: msg)
            scheduleAutoClearError()
            recomputeMicVoiceAvailability()
        case .unavailable(.preparingSession):
            return
        case .unavailable(.hostNotReady):
            detectAndStoreAppContext()
            beginFlowStart()
        case .recording, .processing:
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
        FlowSessionBridge.setRecordingState(.stopped)
        debug("pressEnded wrote .stopped (readback=\(FlowSessionBridge.recordingState().rawValue))")
        state.phase = .processing
        state.lastTranscript = ExtL10n.string("keyboard.flow.transcribing")
        recomputeMicVoiceAvailability()
        startFlowResultWatchdog()
    }

    func beginFlowStart() {
        guard !isPendingFlowStart else { return }
        isPendingFlowStart = true
        isFlowRecording = false
        flowStartDeadline = Date().timeIntervalSince1970 + FlowWatchdog.startTimeout
        state.lastTranscript = ExtL10n.string("keyboard.flow.startingSession")
        recomputeMicVoiceAvailability()
        openHostApp("startflow")
        startFlowStartWatchdog()
        debug("beginFlowStart")
    }

    func handleHostAppOpenResult(path: String, success: Bool) {
        debug("openHostApp path=\(path) success=\(success)")
        guard !success else { return }

        // The open genuinely failed (iOS blocked it / no Full Access). Don't
        // let the 30s watchdog spin — cancel the pending start immediately and
        // guide the user to open OSGKeyboard manually.
        if path == "startflow", isPendingFlowStart {
            isPendingFlowStart = false
            flowStartDeadline = 0
            stopFlowWatchdog()
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
                FlowSessionBridge.setRecordingState(.aborted)
                ExtensionScreenWakeLock.release()
            }
            isFlowRecording = false
            isPendingFlowStart = false
            stopUtteranceCountdown()
            stopFlowWatchdog()
            state.level = 0
            recomputeMicVoiceAvailability()
        }
    }

    // MARK: - Private

    private func consumePendingFlowDeliveryIfNeeded() {
        if isAwaitingFlowResult {
            if let delivery = FlowSessionBridge.consumeTranscriptionDelivery() {
                isAwaitingFlowResult = false
                stopFlowWatchdog()
                textInserter.handleFlowTranscript(delivery)
                return
            }
            if let error = FlowSessionBridge.consumeTranscriptionError() {
                isAwaitingFlowResult = false
                stopFlowWatchdog()
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

    /// When the host process died mid-utterance, abort local recording / waiting
    /// so the user is not stuck until the long result watchdog fires.
    private func recoverFromDeadHostIfNeeded() {
        guard FlowSessionBridge.isHostStale() else { return }

        if isFlowRecording {
            isFlowRecording = false
            stopUtteranceCountdown()
            ExtensionScreenWakeLock.release()
            FlowSessionBridge.setRecordingState(.aborted)
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
        isAwaitingFlowResult = false
        isFlowRecording = false
        isPendingFlowStart = false
        stopUtteranceCountdown()
        ExtensionScreenWakeLock.release()
        FlowSessionBridge.setRecordingState(.aborted)
        stopFlowWatchdog()
        state.level = 0
        let message = ExtL10n.string("keyboard.flow.hostDisconnected")
        state.phase = .error(.flowSessionExpired, message: message)
        scheduleAutoClearError()
        recomputeMicVoiceAvailability()
        debug("host disconnected while awaiting Flow result")
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

    private func startFlowRecording() {
        recomputeMicVoiceAvailability()
        guard state.micVoiceAvailability.isReady else {
            beginFlowStart()
            return
        }
        isPendingFlowStart = false
        flowStartDeadline = 0
        stopFlowWatchdog()

        FlowSessionBridge.setTranscriptionLanguage(state.localeId)
        FlowSessionBridge.setRecordingState(.recording)
        isFlowRecording = true
        state.lastTranscript = ""
        state.phase = .recording
        recomputeMicVoiceAvailability()
        if let view = wakeLockView() {
            ExtensionScreenWakeLock.acquire(from: view)
        }
        startUtteranceCountdown()
        startFlowLevelWatchdog()
        // Read back in-process to confirm the write landed before we rely on
        // the host polling it out cross-process.
        debug("startFlowRecording wrote .recording (readback=\(FlowSessionBridge.recordingState().rawValue))")
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
        flowStartDeadline = 0
        stopFlowWatchdog()
        state.phase = .idle
        state.lastTranscript = ""
        recomputeMicVoiceAvailability()
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
                    self.flowStartDeadline = 0
                    self.showManualOpenHint(path: "startflow")
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func completeFlowStartHandoff() {
        isPendingFlowStart = false
        flowStartDeadline = 0
        stopFlowWatchdog()
        state.lastTranscript = ""
        refreshSessionState()
        startFlowRecording()
        debug("completeFlowStartHandoff → auto startFlowRecording")
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
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func refreshFlowPartialIfNeeded() {
        guard isFlowRecording || isAwaitingFlowResult else { return }
        switch state.phase {
        case .recording, .processing:
            if let partial = FlowSessionBridge.transcriptionPartial() {
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
                if let delivery = FlowSessionBridge.consumeTranscriptionDelivery() {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.debug("resultWatchdog consumed delivery len=\(delivery.text.count)")
                    self.textInserter.handleFlowTranscript(delivery)
                    return
                }
                if let error = FlowSessionBridge.consumeTranscriptionError() {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.debug("resultWatchdog consumed error kind=\(error.kind.rawValue)")
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
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
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
}
