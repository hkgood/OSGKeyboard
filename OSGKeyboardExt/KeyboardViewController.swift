// KeyboardViewController.swift
// OSGKeyboard · Keyboard Extension
//
// Principal class for the Custom Keyboard Extension. Hosts a single
// SwiftUI tree (`KeyboardRootView`) and drives the recording pipeline:
//
//     host app dictation handoff ──► App Group transcript ──► insertText
//
// Design notes:
//   • The class is `@MainActor` — every UI mutation and `textDocumentProxy`
//     call must happen on main, and Swift 6 strict concurrency forces this.
//   • State is a single `State` ObservableObject; SwiftUI observes it via
//     `@ObservedObject` so we never re-create the hosting root on each tick.
//   • `phase` is a real stored property (no derivation) — the previous
//     "derive from recordStream" shim locked out every press after the first.
//   • Microphone permission is requested *inside* pressBegan, but we still
//     start the rest of the press flow optimistically; if permission is
//     denied we surface a short error and drop back to idle cleanly.

import UIKit
import SwiftUI
import OSGKeyboardShared

@objc(KeyboardViewController)
@MainActor
public final class KeyboardViewController: UIInputViewController {
    private enum FlowWatchdog {
        static let pollIntervalNs: UInt64 = 200_000_000
        /// Give the user time to manually open the host app when auto-jump fails.
        static let startTimeout: TimeInterval = 30
        static let resultTimeout: TimeInterval = 45
    }

    private enum DictationWatchdog {
        static let pollIntervalNs: UInt64 = 400_000_000
        static let timeout: TimeInterval = 45
    }

    // MARK: - View model

    /// Typealias so existing call sites (`KeyboardViewController.State`)
    /// keep compiling unchanged. The actual class lives in
    /// `OSGKeyboardShared` so unit tests can `@testable import` it
    /// without dragging in the `app-extension` linking surface.
    public typealias State = KeyboardState

    // MARK: - State

    private let state = State()
    private let polisher = PolishingService()
    private let persistor = AppGroupPersistor()

    private var hosting: UIHostingController<KeyboardRootView>!
    /// Legacy one-shot handoff (`osgkeyboard://dictate`).
    private var awaitingDictationResult = false
    private var dictationRequestStartedAt: TimeInterval = 0
    private var dictationWatchdogTask: Task<Void, Never>?
    /// Flow session: waiting for host app to come alive after `startflow`.
    private var isPendingFlowStart = false
    private var flowStartDeadline: TimeInterval = 0
    private var isFlowRecording = false
    private var flowWatchdogTask: Task<Void, Never>?
    private var utteranceTimerTask: Task<Void, Never>?
    private var utteranceStartedAt: TimeInterval = 0

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        // Keyboard extension MUST opt in to self-sizing, otherwise
        // our SwiftUI `frame(height:)` is ignored and the keyboard is
        // cropped by the system chrome (Spotlight bar, home indicator).
        inputView?.allowsSelfSizing = true
        installStateActions()
        installSwiftUI()
        loadPersistedConfig()
        consumePendingDictationResultIfNeeded()
        refreshDictationProgressStateIfNeeded()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelPipeline()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        consumePendingDictationResultIfNeeded()
        refreshDictationProgressStateIfNeeded()
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        cancelPipeline()
    }

    public override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        consumePendingDictationResultIfNeeded()
        refreshDictationProgressStateIfNeeded()
    }

    // MARK: - Wiring

    private func installStateActions() {
        state.beginRecording      = { [weak self] in self?.pressBegan() }
        state.endRecording        = { [weak self] in self?.pressEnded() }
        state.tapMic              = { [weak self] in self?.toggleRecording() }
        state.openSettings        = { [weak self] in self?.openHostApp() }
        state.setMode             = { [weak self] m in self?.persistMode(m) }
        state.setLocale           = { [weak self] l in self?.persistLocale(l) }
        state.setEngineMode       = { [weak self] m in self?.persistEngineMode(m) }
        state.insertNewline       = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        state.insertSpace         = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        state.deleteBackward      = { [weak self] in self?.textDocumentProxy.deleteBackward() }
    }

    private func installSwiftUI() {
        let root = KeyboardRootView(state: state)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Pin the host view to a fixed height matching KeyboardRootView.totalHeight.
            // Without this, iOS lets the system chrome (Spotlight, home
            // indicator) bleed into our content. With it, our content area
            // is fully reserved and the keyboard feels intentional.
            host.view.heightAnchor.constraint(equalToConstant: KeyboardRootView.totalHeight)
        ])
        host.didMove(toParent: self)
        self.hosting = host
    }

    private func loadPersistedConfig() {
        switch persistor.load(into: state) {
        case .loaded:
            break
        case .unavailable:
            state.phase = .error(.appGroupUnavailable, message: "App Group 未配置")
        }
    }

    // MARK: - Press handlers

    private func toggleRecording() {
        switch state.phase {
        case .recording:
            pressEnded()
        case .idle, .denied, .error:
            pressBegan()
        case .requestingPermissions, .processing:
            break
        }
    }

    private func pressBegan() {
        switch state.phase {
        case .idle, .denied, .error:
            break
        default:
            return
        }
        guard state.mode != .off else { return }
        guard hasFullAccess else {
            let msg = "请在系统设置中为 OSGKeyboard 开启“允许完全访问”，否则无法使用语音输入"
            state.phase = .error(.unknown(msg), message: msg)
            scheduleAutoClearError()
            return
        }
        guard AppGroup.isAvailable else {
            let msg = "App Group 未配置，键盘无法与主 App 通信。请重新安装并检查签名配置。"
            state.phase = .error(.appGroupUnavailable, message: msg)
            scheduleAutoClearError()
            return
        }

        if FlowSessionBridge.isSessionActive() {
            startFlowRecording()
        } else {
            beginFlowStart()
        }
    }

    private func pressEnded() {
        if isPendingFlowStart {
            cancelPendingFlowStart()
            return
        }
        guard isFlowRecording else { return }

        isFlowRecording = false
        stopUtteranceCountdown()
        FlowSessionBridge.setRecordingState(.stopped)
        state.phase = .processing
        state.lastTranscript = "识别中..."
        startFlowResultWatchdog()
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

    private func beginFlowStart() {
        isPendingFlowStart = true
        isFlowRecording = false
        flowStartDeadline = Date().timeIntervalSince1970 + FlowWatchdog.startTimeout
        state.lastTranscript = "正在启动语音会话..."
        state.phase = .processing
        openHostApp(path: "startflow")
        startFlowStartWatchdog()
        debug("beginFlowStart")
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
                    self.startFlowRecording()
                    return
                }
                let now = Date().timeIntervalSince1970
                if self.flowStartDeadline > 0, now > self.flowStartDeadline {
                    self.isPendingFlowStart = false
                    self.flowStartDeadline = 0
                    self.showManualSettingsHint(path: "startflow")
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
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
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func startFlowResultWatchdog() {
        stopFlowWatchdog()
        let startedAt = Date().timeIntervalSince1970
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if let result = FlowSessionBridge.consumeTranscriptionResult() {
                    self.stopFlowWatchdog()
                    self.handleFlowTranscript(result)
                    return
                }
                if let error = FlowSessionBridge.consumeTranscriptionError() {
                    self.stopFlowWatchdog()
                    self.state.phase = .error(.unknown(error), message: error)
                    self.scheduleAutoClearError()
                    return
                }
                let now = Date().timeIntervalSince1970
                if now - startedAt > FlowWatchdog.resultTimeout {
                    self.stopFlowWatchdog()
                    let msg = "等待识别结果超时，请重试"
                    self.state.phase = .error(.unknown(msg), message: msg)
                    self.scheduleAutoClearError()
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func handleFlowTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.phase = .idle
            state.level = 0
            return
        }
        // Host app already polished when configured; keyboard only inserts.
        textDocumentProxy.insertText(trimmed)
        state.lastTranscript = ""
        state.level = 0
        state.phase = .idle
        debug("flow insert length=\(trimmed.count)")
    }

    private func stopFlowWatchdog() {
        flowWatchdogTask?.cancel()
        flowWatchdogTask = nil
    }

    private func cancelPipeline() {
        if isFlowRecording || isPendingFlowStart {
            if isFlowRecording {
                FlowSessionBridge.setRecordingState(.aborted)
            }
            isFlowRecording = false
            isPendingFlowStart = false
            stopUtteranceCountdown()
            stopFlowWatchdog()
            state.level = 0
        }
        if awaitingDictationResult {
            debug("cancelPipeline ignored while awaiting legacy handoff result")
            return
        }
        if state.phase == .processing {
            state.phase = .idle
        }
    }

    private func handleFinalTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debug("received empty transcript")
            awaitingDictationResult = false
            stopDictationWatchdog()
            state.phase = .idle
            return
        }
        debug("received transcript length=\(trimmed.count)")
        awaitingDictationResult = false
        stopDictationWatchdog()
        // Local engine or transcribe mode: insert directly, no LLM call.
        if state.isLocalEngine || state.mode == .transcribe {
            textDocumentProxy.insertText(trimmed)
            state.lastTranscript = ""
            state.phase = .idle
            return
        }
        // `.polish` (default): call the LLM.
        state.phase = .processing
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let polished = try await self.polisher.polish(trimmed)
                self.textDocumentProxy.insertText(polished)
                self.state.lastTranscript = ""
                self.state.phase = .idle
            } catch let error as LLMError {
                switch error {
                case .noAPIKey:
                    // Don't silently insert the raw transcript — the user
                    // thinks they're getting polished text when really no
                    // key is configured. Show a precise, actionable error.
                    self.state.phase = .error(.llm(error), message: "未配置 API Key · 请在主 App 设置中填写")
                    self.scheduleAutoClearError()
                case .http(401):
                    self.state.phase = .error(.llm(error), message: "API Key 无效 (401) · 请检查主 App 设置")
                    self.scheduleAutoClearError()
                case .http(429), .rateLimited:
                    self.state.phase = .error(.llm(error), message: "API 限流 (429) · 请稍后再试")
                    self.scheduleAutoClearError()
                case .cancelled:
                    // User-initiated cancellation (e.g. mode switch mid-
                    // polish). Do NOT re-insert the original transcript —
                    // the user has already moved on and the partial is
                    // considered discarded.
                    self.state.phase = .idle
                    self.state.lastTranscript = ""
                    return
                default:
                    // Other LLMError variants (transport / decoding /
                    // invalidURL) fall back to raw transcript + generic
                    // error badge, same as the catch-all below.
                    self.textDocumentProxy.insertText(trimmed)
                    self.state.lastTranscript = ""
                    let msg = error.errorDescription ?? "Polishing failed — inserted raw."
                    self.state.phase = .error(.llm(error), message: msg)
                    self.scheduleAutoClearError()
                }
            } catch {
                // Network / timeout / decoding — fall back to the raw
                // transcript so the user still gets their text, with a
                // visible error badge.
                self.textDocumentProxy.insertText(trimmed)
                self.state.lastTranscript = ""
                let msg = (error as? LocalizedError)?.errorDescription
                    ?? "Polishing failed — inserted raw."
                self.state.phase = .error(.unknown(msg), message: msg)
                self.scheduleAutoClearError()
            }
        }
    }

    // MARK: - Persistence

    private func persistMode(_ m: State.InputMode) {
        let isRecording = state.phase == .recording
        state.mode = m
        persistor.persist(mode: m)
        if isRecording {
            if m == .off {
                state.phase = .idle
                state.lastTranscript = ""
            }
        }
    }

    private func persistLocale(_ id: String) {
        state.localeId = id
        persistor.persist(localeId: id)
    }

    private func persistEngineMode(_ mode: String) {
        state.engineMode = mode
        persistor.persist(engineMode: mode)
    }

    // MARK: - Open host app

    private func openHostApp(path: String = "settings") {
        guard hasFullAccess else {
            let msg = "未开启“允许完全访问”，请先在键盘设置中打开"
            state.phase = .error(.unknown(msg), message: msg)
            scheduleAutoClearError()
            return
        }
        guard let url = URL(string: "osgkeyboard://\(path)") else {
            handleHostAppOpenResult(path: path, success: false)
            return
        }
        HostAppLauncher.open(url: url, from: self) { [weak self] success in
            self?.handleHostAppOpenResult(path: path, success: success)
        }
    }

    private func handleHostAppOpenResult(path: String, success: Bool) {
        debug("openHostApp path=\(path) success=\(success)")
        guard !success else { return }

        // Flow start: auto-jump often fails in WeChat/Safari — keep polling
        // so a manually opened host app can still satisfy the session check.
        if path == "startflow", isPendingFlowStart {
            state.lastTranscript = "无法自动跳转，请从主屏幕打开 OSGKeyboard，然后返回继续"
            return
        }

        if path == "dictate" {
            awaitingDictationResult = false
            stopDictationWatchdog()
        }
        showManualSettingsHint(path: path)
    }

    private func consumePendingDictationResultIfNeeded() {
        guard let transcript = DictationBridge.consumePendingTranscript() else { return }
        debug("consumePendingDictationResultIfNeeded success")
        handleFinalTranscript(transcript)
    }

    private func refreshDictationProgressStateIfNeeded() {
        guard awaitingDictationResult, case .processing = state.phase else { return }
        let progress = DictationBridge.currentStatus()
        switch progress.status {
        case .requested:
            state.lastTranscript = state.isLocalEngine
                ? "正在打开 OSGKeyboard（本地转写）..."
                : "正在打开 OSGKeyboard..."
        case .recording:
            state.lastTranscript = state.isLocalEngine
                ? "正在本地录音，请完成后返回当前输入页"
                : "正在录音，请完成后返回当前输入页"
        case .transcribing:
            state.lastTranscript = state.isLocalEngine
                ? "本地识别中，请稍候并返回输入页"
                : "识别中，请稍候并返回输入页"
        case .error:
            let msg = progress.message ?? "录音失败，请重试"
            debug("host returned error: \(msg)")
            awaitingDictationResult = false
            stopDictationWatchdog()
            state.phase = .error(.unknown(msg), message: msg)
            scheduleAutoClearError()
        case .cancelled:
            debug("host cancelled")
            awaitingDictationResult = false
            stopDictationWatchdog()
            state.phase = .idle
        case .done, .idle:
            break
        }
        // Host app can be killed or leave without callback. If status does not
        // advance for too long, fail fast with an actionable retry message.
        let now = Date().timeIntervalSince1970
        let lastProgressAt = progress.updatedAt > 0 ? progress.updatedAt : dictationRequestStartedAt
        if now - lastProgressAt > DictationWatchdog.timeout {
            let timeoutMessage = "等待录音结果超时，请返回 OSGKeyboard 完成录音后重试"
            debug("dictation timeout after \(Int(now - lastProgressAt))s")
            awaitingDictationResult = false
            stopDictationWatchdog()
            DictationBridge.clear()
            state.phase = .error(.unknown(timeoutMessage), message: timeoutMessage)
            scheduleAutoClearError()
        }
    }

    private func showManualSettingsHint(path: String = "settings") {
        let msg: String
        if !hasFullAccess {
            msg = "请先开启 OSGKeyboard 的“允许完全访问”，否则键盘无法跳转到 App"
        } else if path == "settings" {
            msg = "系统拒绝了键盘跳转。请手动打开 OSGKeyboard App 进入设置页"
        } else if path == "startflow" {
            msg = "语音会话未启动。请从主屏幕打开 OSGKeyboard App，返回后再按麦克风"
        } else if state.isLocalEngine {
            msg = "系统拒绝了键盘跳转。请先手动打开 OSGKeyboard 完成本地转写，再返回输入页"
        } else {
            msg = "系统拒绝了键盘跳转。请先手动打开 OSGKeyboard 录音，再返回输入页"
        }
        state.phase = .error(.unknown(msg), message: msg)
        scheduleAutoClearError()
    }

    private func startDictationWatchdog() {
        stopDictationWatchdog()
        dictationWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.awaitingDictationResult {
                self.consumePendingDictationResultIfNeeded()
                self.refreshDictationProgressStateIfNeeded()
                try? await Task.sleep(nanoseconds: DictationWatchdog.pollIntervalNs)
            }
        }
    }

    private func stopDictationWatchdog() {
        dictationWatchdogTask?.cancel()
        dictationWatchdogTask = nil
    }

    private func scheduleAutoClearError() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self else { return }
            // Only transient errors auto-clear. `.denied` is sticky: the
            // user needs the message long enough to read it AND decide
            // whether to tap "去设置" or tap the mic to retry. They
            // dismiss it implicitly by doing either of those things.
            switch self.state.phase {
            case .error:
                self.state.phase = .idle
            default:
                break
            }
        }
    }

    private func debug(_ message: String) {
        #if DEBUG
        print("🎙️[KeyboardVC] \(message)")
        #endif
    }
}
