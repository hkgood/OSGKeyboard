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
    private var utteranceStartedAt: TimeInterval = 0
    private var wasFlowSessionActive = false
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

    func startSessionMonitor() {
        flowSessionMonitorTask?.cancel()
        flowSessionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshSessionState()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopSessionMonitor() {
        flowSessionMonitorTask?.cancel()
        flowSessionMonitorTask = nil
    }

    func refreshSessionState() {
        refreshConfigFromAppGroup()
        refreshFlowPartialIfNeeded()
        consumePendingFlowDeliveryIfNeeded()

        let active = FlowSessionBridge.isSessionActive()
        state.flowSessionActive = active

        if wasFlowSessionActive && !active && !isFlowRecording && !isPendingFlowStart {
            switch state.phase {
            case .recording, .processing:
                break
            default:
                showFlowSessionExpiredHint()
            }
        }
        wasFlowSessionActive = active
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
        guard !state.micDisabled else { return }
        guard hasFullAccess() else {
            let msg = ExtL10n.string("keyboard.error.fullAccessRequired")
            state.phase = .error(.fullAccessRequired, message: msg)
            scheduleAutoClearError()
            return
        }
        guard AppGroup.isAvailable else {
            let msg = ExtL10n.string("keyboard.error.appGroupCommunication")
            state.phase = .error(.appGroupUnavailable, message: msg)
            scheduleAutoClearError()
            return
        }

        detectAndStoreAppContext()

        if FlowSessionBridge.isSessionActive() {
            startFlowRecording()
        } else {
            beginFlowStart()
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
        state.phase = .processing
        state.lastTranscript = ExtL10n.string("keyboard.flow.transcribing")
        startFlowResultWatchdog()
    }

    func beginFlowStart() {
        guard !isPendingFlowStart else { return }
        isPendingFlowStart = true
        isFlowRecording = false
        flowStartDeadline = Date().timeIntervalSince1970 + FlowWatchdog.startTimeout
        state.lastTranscript = ExtL10n.string("keyboard.flow.startingSession")
        state.phase = .processing
        openHostApp("startflow")
        startFlowStartWatchdog()
        debug("beginFlowStart")
    }

    func handleHostAppOpenResult(path: String, success: Bool) {
        debug("openHostApp path=\(path) success=\(success)")
        guard !success else { return }

        if path == "startflow", isPendingFlowStart {
            state.lastTranscript = ExtL10n.string("keyboard.flow.manualOpenHost")
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
                return
            }
        }

        if isPendingFlowStart, FlowSessionBridge.isSessionActive() {
            completeFlowStartHandoff()
        }
    }

    private func showFlowSessionExpiredHint() {
        let message = ExtL10n.string("keyboard.flow.sessionExpired")
        state.phase = .error(.flowSessionExpired, message: message)
        scheduleAutoClearError()
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
    }

    private func startFlowRecording() {
        isPendingFlowStart = false
        flowStartDeadline = 0
        stopFlowWatchdog()

        FlowSessionBridge.setTranscriptionLanguage(state.localeId)
        FlowSessionBridge.setRecordingState(.recording)
        isFlowRecording = true
        state.lastTranscript = ""
        state.phase = .recording
        if let view = wakeLockView() {
            ExtensionScreenWakeLock.acquire(from: view)
        }
        startUtteranceCountdown()
        startFlowLevelWatchdog()
        debug("startFlowRecording")
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
    }

    private func startFlowStartWatchdog() {
        stopFlowWatchdog()
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isPendingFlowStart {
                if FlowSessionBridge.isSessionActive() {
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
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if let delivery = FlowSessionBridge.consumeTranscriptionDelivery() {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.textInserter.handleFlowTranscript(delivery)
                    return
                }
                if let error = FlowSessionBridge.consumeTranscriptionError() {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.state.phase = .error(
                        .fromFlowTranscription(error),
                        message: error.message
                    )
                    self.scheduleAutoClearError()
                    return
                }
                self.refreshFlowPartialIfNeeded()
                let now = Date().timeIntervalSince1970
                if now - startedAt > resultTimeout {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    let msg = ExtL10n.string("keyboard.flow.resultTimeout")
                    self.state.phase = .error(.flowResultTimeout, message: msg)
                    self.scheduleAutoClearError()
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
