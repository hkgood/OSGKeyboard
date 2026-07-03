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

        static func resultTimeout(
            engineMode: String,
            localASRBackend: LocalASRBackend
        ) -> TimeInterval {
            FlowSessionKeys.keyboardResultTimeout(
                engineMode: engineMode,
                localASRBackend: localASRBackend
            )
        }
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
    private var wasFlowSessionActive = false
    private var flowSessionMonitorTask: Task<Void, Never>?
    private var flowSessionDarwinObserver: FlowSessionDarwinObserver?
    private var configDarwinObserver: FlowSessionDarwinObserver?
    /// Grace period after a chip-side translation write during which the
    /// 1 Hz App Group poll must not overwrite `translationTargetLocaleId`.
    private var translationConfigProtectedUntil: Date?
    private var polishScenarioConfigProtectedUntil: Date?
    private var isAwaitingFlowResult = false
    private var lastFlowAutoStartAttempt: TimeInterval = 0
    private static let flowAutoStartCooldown: TimeInterval = 20
    /// Drives the keyboard slot height on `view` (priority 999).
    private var keyboardHeightConstraint: NSLayoutConstraint?
    /// Runtime value read from `UIView-Encapsulated-Layout-Height` (varies by device).
    private var systemEncapsulatedHeight: CGFloat = 228

    private var targetKeyboardHeight: CGFloat {
        KeyboardRootView.totalHeight
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        installKeyboardHeight()
        configureDictationBehavior()
        installStateActions()
        installSwiftUI()
        loadPersistedConfig()
        consumePendingDictationResultIfNeeded()
        refreshDictationProgressStateIfNeeded()
        installFlowSessionDarwinObserver()
        installConfigDarwinObserver()
        refreshFlowSessionState()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopFlowSessionMonitor()
        // Preserve flow handoff / recording / result polling across the
        // intentional jump to the host app (keyboard extension pauses here).
        if isPendingFlowStart || isFlowRecording || isAwaitingFlowResult || awaitingDictationResult {
            return
        }
        ExtensionScreenWakeLock.releaseAll()
        cancelPipeline()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        configureDictationBehavior()
        KeyboardSetupBridge.markExtensionAppearance(hasFullAccess: hasFullAccess)
        consumePendingDictationResultIfNeeded()
        refreshDictationProgressStateIfNeeded()
        refreshFlowSessionState()
        startFlowSessionMonitor()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        applyPresentationHeightOffset()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Presentation finished — lock to the true content-driven height.
        keyboardHeightConstraint?.constant = targetKeyboardHeight
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

    // MARK: - System keyboard chrome

    /// Tell iOS this keyboard provides its own dictation entry (centre mic).
    /// When `true`, the system dictation key in the bottom-right is not shown.
    private func configureDictationBehavior() {
        hasDictationKey = true
    }

    // MARK: - Wiring

    private func installStateActions() {
        state.beginRecording      = { [weak self] in self?.pressBegan() }
        state.endRecording        = { [weak self] in self?.pressEnded() }
        state.tapMic              = { [weak self] in self?.toggleRecording() }
        state.openSettings        = { [weak self] in self?.openHostApp() }
        state.startFlowSession    = { [weak self] in self?.beginFlowStart() }
        state.setMode             = { [weak self] m in self?.persistMode(m) }
        state.setLocale           = { [weak self] l in self?.persistLocale(l) }
        state.setEngineMode       = { [weak self] m in self?.persistEngineMode(m) }
        state.setLocalASRBackend  = { [weak self] b in self?.persistLocalASRBackend(b) }
        // v0.2.1 follow-up: removed `setTranslationEnabled` — the chip
        // / picker only writes the locale id now; `enabled` is derived.
        state.setTranslationTargetLocaleId = { [weak self] id in self?.persistTranslationTargetLocaleId(id) }
        state.setPolishScenarioId = { [weak self] id in self?.persistPolishScenarioId(id) }
        state.insertNewline       = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        state.insertSpace         = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        state.deleteBackward      = { [weak self] in self?.textDocumentProxy.deleteBackward() }
    }

    /// Reserve keyboard height on `view`. During presentation iOS adds a
    /// private encapsulated height; `viewIsAppearing` applies the community
    /// offset trick (target − encapsulated) so the slot lands at `target`.
    private func installKeyboardHeight() {
        let constraint = view.heightAnchor.constraint(
            equalToConstant: targetKeyboardHeight
        )
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

    /// Read the system encapsulated height and prime our constraint so iOS
    /// presentation math (custom + encapsulated) equals `targetKeyboardHeight`.
    /// See: https://developer.apple.com/forums/thread/799003
    private func applyPresentationHeightOffset() {
        if let encapsulated = view.constraints.first(where: { constraint in
            constraint.firstItem as? UIView === view
                && constraint.firstAttribute == .height
                && constraint !== keyboardHeightConstraint
        }) {
            systemEncapsulatedHeight = encapsulated.constant
        }
        let primed = targetKeyboardHeight - systemEncapsulatedHeight
        keyboardHeightConstraint?.constant = max(0, primed)
    }

    private func installSwiftUI() {
        let root = KeyboardRootView(state: state)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.clipsToBounds = false
        // Keep keyboard layout anchored to the top edge across keyboard
        // switches — don't let UIHostingController re-inset for safe area.
        host.view.insetsLayoutMarginsFromSafeArea = false
        host.safeAreaRegions = []
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.hosting = host
    }

    private func loadPersistedConfig() {
        switch persistor.load(into: state) {
        case .loaded:
            break
        case .unavailable:
            state.phase = .error(
                .appGroupUnavailable,
                message: ExtL10n.string("keyboard.error.appGroupUnavailable")
            )
        }
    }

    // MARK: - Flow session monitor

    private func installFlowSessionDarwinObserver() {
        flowSessionDarwinObserver = FlowSessionDarwinObserver { [weak self] in
            self?.refreshFlowSessionState()
        }
    }

    private func startFlowSessionMonitor() {
        flowSessionMonitorTask?.cancel()
        flowSessionMonitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refreshFlowSessionState()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopFlowSessionMonitor() {
        flowSessionMonitorTask?.cancel()
        flowSessionMonitorTask = nil
    }

    private func installConfigDarwinObserver() {
        configDarwinObserver = FlowSessionDarwinObserver(
            notificationName: AppGroupConfigDarwin.notificationName
        ) { [weak self] in
            self?.refreshConfigFromAppGroup()
        }
    }

    private func refreshConfigFromAppGroup() {
        persistor.refreshRuntimeFlags(
            into: state,
            protectTranslationUntil: translationConfigProtectedUntil,
            protectPolishScenarioUntil: polishScenarioConfigProtectedUntil
        )
    }

    private func refreshFlowSessionState() {
        persistor.refreshRuntimeFlags(
            into: state,
            protectTranslationUntil: translationConfigProtectedUntil,
            protectPolishScenarioUntil: polishScenarioConfigProtectedUntil
        )
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

        if !active {
            maybeAutoStartFlowSession()
        }
    }

    /// Pick up transcripts/errors the host wrote while the extension was paused.
    private func consumePendingFlowDeliveryIfNeeded() {
        if isAwaitingFlowResult {
            if let delivery = FlowSessionBridge.consumeTranscriptionDelivery() {
                isAwaitingFlowResult = false
                stopFlowWatchdog()
                handleFlowTranscript(delivery)
                return
            }
            if let error = FlowSessionBridge.consumeTranscriptionError() {
                isAwaitingFlowResult = false
                stopFlowWatchdog()
                state.phase = .error(.unknown(error), message: error)
                scheduleAutoClearError()
                return
            }
        }

        if isPendingFlowStart, FlowSessionBridge.isSessionActive() {
            completeFlowStartHandoff()
        }
    }

    /// When the host session is down, proactively jump to the app to start it.
    private func maybeAutoStartFlowSession() {
        guard !FlowSessionBridge.isSessionActive() else { return }
        guard !isPendingFlowStart, !isFlowRecording, !isAwaitingFlowResult else { return }
        guard hasFullAccess, AppGroup.isAvailable else { return }
        guard case .idle = state.phase else { return }

        let now = Date().timeIntervalSince1970
        guard now - lastFlowAutoStartAttempt >= Self.flowAutoStartCooldown else { return }
        lastFlowAutoStartAttempt = now
        beginFlowStart()
    }

    private func showFlowSessionExpiredHint() {
        let message = ExtL10n.string("keyboard.flow.sessionExpired")
        state.phase = .error(.unknown(message), message: message)
        scheduleAutoClearError()
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
        guard hasFullAccess else {
            let msg = ExtL10n.string("keyboard.error.fullAccessRequired")
            state.phase = .error(.unknown(msg), message: msg)
            scheduleAutoClearError()
            return
        }
        guard AppGroup.isAvailable else {
            let msg = ExtL10n.string("keyboard.error.appGroupCommunication")
            state.phase = .error(.appGroupUnavailable, message: msg)
            scheduleAutoClearError()
            return
        }

        // v0.3.0: detect the app context (code / email / chat / doc)
        // *before* either path. The Flow session's polisher and the
        // legacy handoff's polisher both read this from the App
        // Group. Cheap (heuristic over ≤ 2 KB), safe to run every
        // press of the mic.
        detectAndStoreAppContext()

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
        ExtensionScreenWakeLock.release()
        FlowSessionBridge.setRecordingState(.stopped)
        state.phase = .processing
        state.lastTranscript = ExtL10n.string("keyboard.flow.transcribing")
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
        ExtensionScreenWakeLock.acquire(from: view)
        startUtteranceCountdown()
        startFlowLevelWatchdog()
        debug("startFlowRecording")
    }

    /// v0.3.0: run the 3-fallback context detector on the text
    /// already at the cursor and persist the result to the App
    /// Group. Cheap (heuristic over ≤ 2 KB of preceding text) so
    /// safe to run on every press of the mic; we deliberately
    /// avoid hitting the App Group on every keystroke.
    private func detectAndStoreAppContext() {
        let preceding = textDocumentProxy.documentContextBeforeInput
        let store = AppGroupStore()
        let detector = AppContextDetector()
        let context = detector.detect(
            precedingText: preceding,
            storedCache: store.detectedAppContext
        )
        store.setDetectedAppContext(context)
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
        guard !isPendingFlowStart else { return }
        isPendingFlowStart = true
        isFlowRecording = false
        flowStartDeadline = Date().timeIntervalSince1970 + FlowWatchdog.startTimeout
        state.lastTranscript = ExtL10n.string("keyboard.flow.startingSession")
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
                    self.completeFlowStartHandoff()
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

    /// Session is live — return to idle so the user can tap again to record.
    private func completeFlowStartHandoff() {
        isPendingFlowStart = false
        flowStartDeadline = 0
        stopFlowWatchdog()
        state.lastTranscript = ""
        state.phase = .idle
        refreshFlowSessionState()
        debug("completeFlowStartHandoff")
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
        isAwaitingFlowResult = true
        let startedAt = Date().timeIntervalSince1970
        let resultTimeout = FlowWatchdog.resultTimeout(
            engineMode: state.engineMode,
            localASRBackend: state.localASRBackend
        )
        flowWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if let delivery = FlowSessionBridge.consumeTranscriptionDelivery() {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.handleFlowTranscript(delivery)
                    return
                }
                if let error = FlowSessionBridge.consumeTranscriptionError() {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    self.state.phase = .error(.unknown(error), message: error)
                    self.scheduleAutoClearError()
                    return
                }
                let now = Date().timeIntervalSince1970
                if now - startedAt > resultTimeout {
                    self.isAwaitingFlowResult = false
                    self.stopFlowWatchdog()
                    let msg = ExtL10n.string("keyboard.flow.resultTimeout")
                    self.state.phase = .error(.unknown(msg), message: msg)
                    self.scheduleAutoClearError()
                    return
                }
                try? await Task.sleep(nanoseconds: FlowWatchdog.pollIntervalNs)
            }
        }
    }

    private func handleFlowTranscript(_ delivery: TranscriptionDelivery) {
        let trimmed = delivery.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            state.phase = .idle
            state.level = 0
            return
        }
        // Host app already polished when configured; keyboard only inserts.
        textDocumentProxy.insertText(trimmed)
        state.lastTranscript = ""
        state.level = 0
        if let warning = delivery.polishWarning {
            state.phase = .error(.unknown(warning), message: warning)
            scheduleAutoClearError()
        } else {
            state.phase = .idle
        }
        debug("flow insert length=\(trimmed.count)")
    }

    private func stopFlowWatchdog() {
        flowWatchdogTask?.cancel()
        flowWatchdogTask = nil
    }

    private func cancelPipeline() {
        if isAwaitingFlowResult || awaitingDictationResult {
            return
        }
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

    private func handleFinalTranscript(_ delivery: TranscriptionDelivery) {
        let trimmed = delivery.text.trimmingCharacters(in: .whitespacesAndNewlines)
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

        let runtimeStore = AppGroupStore()
        guard runtimeStore.shouldRunCloudLLMStep else {
            textDocumentProxy.insertText(trimmed)
            state.lastTranscript = ""
            if let warning = delivery.polishWarning {
                state.phase = .error(.unknown(warning), message: warning)
                scheduleAutoClearError()
            } else {
                state.phase = .idle
            }
            return
        }

        // Cloud engine, or local engine with cloud polish / translation.
        state.phase = .processing
        Task { @MainActor [weak self] in
            guard let self else { return }
            let polishMode = runtimeStore.polishModeForPipeline
            let overrideProviderId = runtimeStore.polishProviderIdOverride
            do {
                let polished = try await self.polisher.polish(
                    trimmed,
                    mode: polishMode,
                    providerIdOverride: overrideProviderId
                )
                self.textDocumentProxy.insertText(polished)
                self.state.lastTranscript = ""
                self.state.phase = .idle
            } catch let error as LLMError {
                switch error {
                case .noAPIKey:
                    // Don't silently insert the raw transcript — the user
                    // thinks they're getting polished text when really no
                    // key is configured. Show a precise, actionable error.
                    self.state.phase = .error(.llm(error), message: ExtL10n.string("keyboard.error.llm.noApiKey"))
                    self.scheduleAutoClearError()
                case .http(401):
                    self.state.phase = .error(.llm(error), message: ExtL10n.string("keyboard.error.llm.unauthorized"))
                    self.scheduleAutoClearError()
                case .http(429), .rateLimited:
                    self.state.phase = .error(.llm(error), message: ExtL10n.string("keyboard.error.llm.rateLimited"))
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
            } catch let polishError as PolishingService.PolishError where polishError == .missingAPIKey {
                // v0.2.0: local engine + cloud polish toggle on, but the
                // user hasn't entered an API key. Insert the raw transcript
                // (so the user doesn't lose what they said) and surface the
                // same "fill in your key" hint we use in the cloud path.
                self.textDocumentProxy.insertText(trimmed)
                self.state.lastTranscript = ""
                self.state.phase = .error(
                    .llm(.noAPIKey),
                    message: ExtL10n.string("keyboard.error.llm.noApiKey")
                )
                self.scheduleAutoClearError()
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

    private func persistLocalASRBackend(_ backend: LocalASRBackend) {
        state.localASRBackend = backend
        persistor.persist(localASRBackend: backend)
    }

    // MARK: - Translation persistence

    /// v0.2.1 follow-up: persist translation target locale id. Resolved
    /// via `TranslationLanguageCatalog.resolve` so a stale persisted
    /// value (e.g. a removed locale id from an older build) still finds
    /// the right entry instead of crashing the picker. Translation's
    /// "on/off" state is now derived from this id (== `offLocaleId`
    /// means off), so there's no separate toggle to persist.
    private func persistTranslationTargetLocaleId(_ id: String) {
        let resolved = TranslationLanguageCatalog.resolve(id).id
        state.translationTargetLocaleId = resolved
        translationConfigProtectedUntil = Date().addingTimeInterval(2.5)
        persistor.persist(translationTargetLocaleId: resolved)
    }

    private func persistPolishScenarioId(_ id: String) {
        let resolved = PolishScenarioCatalog.resolve(id).id
        state.polishScenarioId = resolved
        polishScenarioConfigProtectedUntil = Date().addingTimeInterval(2.5)
        persistor.persist(polishScenarioId: resolved)
    }

    // MARK: - Open host app

    private func openHostApp(path: String = "settings") {
        guard hasFullAccess else {
            let msg = ExtL10n.string("keyboard.error.fullAccessForJump")
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
            state.lastTranscript = ExtL10n.string("keyboard.flow.manualOpenHost")
            return
        }

        if path == "dictate" {
            awaitingDictationResult = false
            stopDictationWatchdog()
        }
        showManualSettingsHint(path: path)
    }

    private func consumePendingDictationResultIfNeeded() {
        guard let delivery = DictationBridge.consumePendingDelivery() else { return }
        debug("consumePendingDictationResultIfNeeded success")
        handleFinalTranscript(delivery)
    }

    private func refreshDictationProgressStateIfNeeded() {
        guard awaitingDictationResult, case .processing = state.phase else { return }
        let progress = DictationBridge.currentStatus()
        switch progress.status {
        case .requested:
            state.lastTranscript = state.isLocalEngine
                ? ExtL10n.string("keyboard.dictation.openingLocal")
                : ExtL10n.string("keyboard.dictation.opening")
        case .recording:
            state.lastTranscript = state.isLocalEngine
                ? ExtL10n.string("keyboard.dictation.recordingLocal")
                : ExtL10n.string("keyboard.dictation.recording")
        case .transcribing:
            state.lastTranscript = state.isLocalEngine
                ? ExtL10n.string("keyboard.dictation.transcribingLocal")
                : ExtL10n.string("keyboard.dictation.transcribing")
        case .error:
            let msg = progress.message ?? ExtL10n.string("keyboard.dictation.failed")
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
            let timeoutMessage = ExtL10n.string("keyboard.dictation.resultTimeout")
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
            msg = ExtL10n.string("keyboard.error.fullAccessForJump")
        } else if path == "settings" {
            msg = ExtL10n.string("keyboard.error.manualOpenSettings")
        } else if path == "startflow" {
            msg = ExtL10n.string("keyboard.error.manualOpenForFlow")
        } else if state.isLocalEngine {
            msg = ExtL10n.string("keyboard.error.manualOpenDictateLocal")
        } else {
            msg = ExtL10n.string("keyboard.error.manualOpenDictate")
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
