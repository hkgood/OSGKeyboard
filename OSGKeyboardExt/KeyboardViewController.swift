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
import os

/// Unified log for the keyboard extension. Visible in Console.app when
/// filtered by `subsystem: com.osgkeyboard.ios`. Note: plain `print`
/// from an extension process does NOT reliably reach Xcode's console
/// (the debugger is usually attached to the host app, not the
/// extension), which is why extension-side diagnostics must go through
/// `os.Logger` to be observable.
private let keyboardExtLog = Logger(subsystem: "com.osgkeyboard.ios", category: "KeyboardExt")

private final class KeyboardHostingController: UIHostingController<KeyboardRootView> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }
}

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

    private var hosting: UIHostingController<KeyboardRootView>?
    /// Centred "拖动移动光标" hint, stacked above the SwiftUI tree.
    private var cursorDragHintLabel: UILabel?
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
    /// Serializes caret moves so `textDocumentProxy` keeps up with drag events.
    private var pendingHorizontalCursorSteps = 0
    private var pendingVerticalCursorSteps = 0
    private var cursorMoveFlushScheduled = false
    /// Fires once per vertical chunk step during a cursor drag.
    private let cursorLineHaptic = UIImpactFeedbackGenerator(style: .light)
    /// Characters moved per vertical drag step (up = back, down = forward).
    private static let cursorVerticalChunkSize = 20
    /// Grace period after a chip-side translation write during which the
    /// 1 Hz App Group poll must not overwrite `translationTargetLocaleId`.
    private var translationConfigProtectedUntil: Date?
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
        keyboardExtLog.info("viewDidLoad — extension booted (build marker: cursor-drag diag)")
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
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
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        configureDictationBehavior()
        KeyboardSetupBridge.markExtensionAppearance(hasFullAccess: hasFullAccess)
        consumePendingDictationResultIfNeeded()
        refreshDictationProgressStateIfNeeded()
        refreshFlowSessionState()
        startFlowSessionMonitor()
        // v0.3.0: re-mirror onboarding + app context from the App
        // Group every time we appear. The user may have just returned
        // from Settings.app or the host app, and the App Group is the
        // only thing both processes see consistently.
        syncOnboardingStateFromAppGroup()
        refreshConfigFromAppGroup()
        // Auto-advance past step 3 ("Enable Keyboard") if the user has
        // enabled the keyboard in Settings.app while we were away.
        // This is the "automatic return from jump" feature: no manual
        // "Continue" tap needed.
        autoAdvancePastKeyboardSetupStepIfNeeded()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        applyPresentationHeightOffset()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableSystemGestureDelays()
        // Presentation finished — lock to the true content-driven height.
        keyboardHeightConstraint?.constant = targetKeyboardHeight
    }

    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    public override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        hosting
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

    /// Keyboard extensions can lose or delay touches near the screen
    /// edges because system edge-pan recognizers get first refusal.
    /// Deferring edges above is the intent; this sweep removes delay
    /// flags from recognizers already attached to the host hierarchy.
    private func disableSystemGestureDelays() {
        disableGestureDelays(in: view)
        var parent = view.superview
        while let current = parent {
            disableGestureDelays(in: current)
            parent = current.superview
        }
        if let window = view.window {
            disableGestureDelays(in: window)
            if let rootView = window.rootViewController?.view {
                disableGestureDelays(in: rootView)
            }
        }
    }

    private func disableGestureDelays(in targetView: UIView) {
        targetView.gestureRecognizers?.forEach { recognizer in
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.cancelsTouchesInView = false
            if recognizer is UIScreenEdgePanGestureRecognizer {
                recognizer.isEnabled = false
            }
        }
        targetView.subviews.forEach(disableGestureDelays)
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
        // / picker now writes the locale id directly; `enabled` is derived.
        state.setTranslationTargetLocaleId = { [weak self] id in self?.persistTranslationTargetLocaleId(id) }
        // v0.3.0: in-keyboard onboarding actions. Persist via the App
        // Group so the host app's `ProviderConfig` stays in sync (and
        // the next launch of the host app opens at the same page).
        state.advanceOnboarding   = { [weak self] in self?.advanceOnboarding() }
        state.completeOnboarding   = { [weak self] in self?.completeOnboarding() }
        state.requestMicPermission   = { [weak self] in self?.requestMicPermissionFromExtension() }
        state.requestSpeechPermission = { [weak self] in self?.requestSpeechPermissionFromExtension() }
        state.openSystemSettings   = { [weak self] in self?.openSystemSettingsFromExtension() }
        state.insertNewline       = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        state.insertSpace         = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        state.deleteBackward      = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        state.moveCursorHorizontal = { [weak self] steps in
            self?.moveCursorHorizontally(by: steps)
        }
        state.moveCursorVertical = { [weak self] steps in
            self?.moveCursorVertically(by: steps)
        }
        state.setCursorDragActive = { [weak self] active in
            self?.setCursorDragActive(active)
        }
    }

    private func setCursorDragActive(_ active: Bool) {
        state.cursorDragActive = active
        updateCursorDragWash(active: active)
    }

    private func updateCursorDragWash(active: Bool) {
        if active {
            cursorLineHaptic.prepare()
        }
        layoutCursorDragChrome()
        // Gradient wash intentionally not shown — only the centred hint.
        guard let hint = cursorDragHintLabel else { return }
        if active {
            hint.isHidden = false
            UIView.animate(withDuration: 0.12) { hint.alpha = 1 }
        } else {
            UIView.animate(withDuration: 0.12, animations: { hint.alpha = 0 }) { [weak self] _ in
                guard let self, !self.state.cursorDragActive else { return }
                hint.isHidden = true
            }
        }
    }

    private func moveCursorHorizontally(by steps: Int) {
        guard steps != 0 else { return }
        pendingHorizontalCursorSteps += steps
        scheduleCursorMoveFlush()
    }

    private func moveCursorVertically(by steps: Int) {
        guard steps != 0 else { return }
        pendingVerticalCursorSteps += steps
        scheduleCursorMoveFlush()
    }

    private func scheduleCursorMoveFlush() {
        guard !cursorMoveFlushScheduled else { return }
        cursorMoveFlushScheduled = true
        // Give the text-document proxy one run-loop turn between drag
        // samples so caret updates are not dropped. Runs on the main
        // queue (not a Task) to avoid `unsafeForcedSync` proxy access.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { [weak self] in
            guard let self else { return }
            self.cursorMoveFlushScheduled = false

            let horizontal = self.pendingHorizontalCursorSteps
            let vertical = self.pendingVerticalCursorSteps
            self.pendingHorizontalCursorSteps = 0
            self.pendingVerticalCursorSteps = 0

            if horizontal != 0 {
                keyboardExtLog.info("adjustTextPosition h=\(horizontal)")
                self.textDocumentProxy.adjustTextPosition(byCharacterOffset: horizontal)
            }

            if vertical != 0 {
                self.applyVerticalCursorSteps(vertical)
            }

            if self.pendingHorizontalCursorSteps != 0 || self.pendingVerticalCursorSteps != 0 {
                self.scheduleCursorMoveFlush()
            }
        }
    }

    private func applyVerticalCursorSteps(_ steps: Int) {
        let direction = steps > 0 ? 1 : -1
        var remaining = abs(steps)
        let chunk = Self.cursorVerticalChunkSize

        while remaining > 0 {
            textDocumentProxy.adjustTextPosition(byCharacterOffset: direction * chunk)
            cursorLineHaptic.impactOccurred()
            cursorLineHaptic.prepare()
            remaining -= 1
        }
    }

    // MARK: - Onboarding persistence (v0.3.0)

    private func advanceOnboarding() {
        let store = AppGroupStore()
        let nextPage = min(4, store.onboardingPage + 1)
        store.setOnboardingPage(nextPage)
        state.onboardingPage = nextPage
    }

    private func completeOnboarding() {
        let store = AppGroupStore()
        store.setHasCompletedOnboarding(true)
        store.setOnboardingPage(4)
        state.hasCompletedOnboarding = true
        state.onboardingPage = 4
    }

    // MARK: - Permission requests from the extension (v0.3.0)

    /// The keyboard extension cannot present `AVAudioSession` /
    /// `SFSpeechRecognizer` permission dialogs directly. It *can* read
    /// the current status and tell the user to grant them from the
    /// host app — which the overlay's step 1/2 copy already does.
    /// This method is kept as a no-op stub so the action hook exists
    /// and we can fill in the right behaviour if iOS ever relaxes the
    /// sandbox (currently the system dialog is only presented when
    /// the relevant API is first invoked from the host app, not the
    /// extension).
    private func requestMicPermissionFromExtension() {
        // Status is read on the next `viewWillAppear` via
        // `KeyboardSetupBridge`; the overlay advances optimistically.
    }

    private func requestSpeechPermissionFromExtension() {
        // Same as above — read on next `viewWillAppear`.
    }

    /// Open `Settings.app` so the user can flip the "Allow Full Access"
    /// / "OSGKeyboard" toggles. `UIApplication.openSettingsURLString`
    /// is the only system URL the keyboard extension is allowed to
    /// open via `extensionContext`.
    private func openSystemSettingsFromExtension() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        HostAppLauncher.open(url: url, from: self) { _ in }
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
        let host = KeyboardHostingController(rootView: root)
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

        // Cursor-drag chrome: only a centred hint label above the SwiftUI
        // tree (non-interactive so the pads underneath still receive
        // touches). The green gradient wash was removed — it was too hard to
        // align cleanly with the system keyboard's rounded top edge.
        let hint = UILabel()
        hint.text = ExtL10n.string("keyboard.cursorDrag.centerHint")
        hint.font = .systemFont(ofSize: 22, weight: .medium)
        hint.textColor = UIColor.label.withAlphaComponent(0.10)
        hint.textAlignment = .center
        hint.numberOfLines = 1
        hint.adjustsFontSizeToFitWidth = true
        hint.minimumScaleFactor = 0.7
        hint.isUserInteractionEnabled = false
        hint.isHidden = true
        hint.alpha = 0
        view.addSubview(hint)

        self.cursorDragHintLabel = hint
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCursorDragChrome()
    }

    private func layoutCursorDragChrome() {
        cursorDragHintLabel?.frame = view.bounds
    }

    private func loadPersistedConfig() {
        switch persistor.load(into: state) {
        case .loaded:
            keyboardExtLog.info(
                "config loaded — cursorDragNavigationEnabled=\(self.state.cursorDragNavigationEnabled)"
            )
        case .unavailable:
            state.phase = .error(
                .appGroupUnavailable,
                message: ExtL10n.string("keyboard.error.appGroupUnavailable")
            )
        }
        syncOnboardingStateFromAppGroup()
    }

    // MARK: - Onboarding / app-context sync (v0.3.0)

    /// Mirror the persisted onboarding flags from the App Group into
    /// `KeyboardState`. Called both at boot (`loadPersistedConfig`) and
    /// on every `viewWillAppear` so the overlay reflects what the user
    /// did while the keyboard was paused (e.g. toggling permissions
    /// in the host app's onboarding view).
    private func syncOnboardingStateFromAppGroup() {
        let store = AppGroupStore()
        state.hasCompletedOnboarding = store.hasCompletedOnboarding
        state.onboardingPage = store.onboardingPage
    }

    /// If the user has finished the "Enable Keyboard" step (i.e. the
    /// keyboard is now in the system list with full access), and the
    /// overlay is currently sitting on that step, advance to the API
    /// step silently. This is what makes the "jump out → come back"
    /// flow feel automatic even though iOS won't switch us back.
    private func autoAdvancePastKeyboardSetupStepIfNeeded() {
        guard !state.hasCompletedOnboarding else { return }
        // step index 3 = "Enable Keyboard"
        guard state.onboardingPage == 3 else { return }
        guard KeyboardSetupBridge.isReadyForOnboardingSkip else { return }
        let store = AppGroupStore()
        store.setOnboardingPage(4)
        state.onboardingPage = 4
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
            protectTranslationUntil: translationConfigProtectedUntil
        )
    }

    private func refreshFlowSessionState() {
        persistor.refreshRuntimeFlags(
            into: state,
            protectTranslationUntil: translationConfigProtectedUntil
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
        guard !state.micDisabled else { return }
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
            let preceding = self.textDocumentProxy.documentContextBeforeInput
            let polishContext = PolishContext(
                appContext: runtimeStore.detectedAppContext?.context ?? .unknown,
                intensity: runtimeStore.polishIntensity,
                precedingText: preceding
            )
            do {
                let polished = try await self.polisher.polish(
                    trimmed,
                    mode: polishMode,
                    providerIdOverride: overrideProviderId,
                    context: polishContext
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
                self.textDocumentProxy.insertText(trimmed)
                self.state.lastTranscript = ""
                let message = runtimeStore.engineMode == "local"
                    ? ExtL10n.string("keyboard.error.llm.localPolishUnavailable")
                    : ExtL10n.string("keyboard.error.llm.noApiKey")
                self.state.phase = .error(.llm(.noAPIKey), message: message)
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
        keyboardExtLog.info("\(message, privacy: .public)")
    }
}
