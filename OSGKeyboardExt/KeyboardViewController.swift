// KeyboardViewController.swift
// OSGKeyboard · Keyboard Extension
//
// Principal class for the Custom Keyboard Extension. Hosts a single
// SwiftUI tree (`KeyboardRootView`) and wires Flow voice input:
//
//     host app Flow session ──► App Group transcript ──► insertText
//
// Design notes:
//   • The class is `@MainActor` — every UI mutation and `textDocumentProxy`
//     call must happen on main, and Swift 6 strict concurrency forces this.
//   • State is a single `State` ObservableObject; SwiftUI observes it via
//     `@ObservedObject` so we never re-create the hosting root on each tick.
//   • `phase` is a real stored property (no derivation) — the previous
//     "derive from recordStream" shim locked out every press after the first.

import UIKit
import SwiftUI
import Combine
import OSGKeyboardShared

private final class KeyboardHostingController: UIHostingController<KeyboardSurfaceRoot> {
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
    public typealias State = KeyboardState

    private let state = State()
    private let typingSession = TypingSessionController()
    private let persistor = AppGroupPersistor()

    private var hosting: UIHostingController<KeyboardSurfaceRoot>?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var systemEncapsulatedHeight: CGFloat = 228
    private var cancellables = Set<AnyCancellable>()

    private var textInserter: KeyboardTextInserter!
    private var flowCoordinator: KeyboardFlowCoordinator!
    private var configSync: KeyboardConfigSync!
    private var cursorDrag: CursorDragController!

    private var targetKeyboardHeight: CGFloat {
        KeyboardSurfaceRoot.height(for: state.surface)
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        // Voice-first keyboard — hide the misleading "English" subtitle in Settings.
        primaryLanguage = "mis"
        OSGLog.keyboardExt.info("viewDidLoad — extension booted")
        // Deliberately NO CustomLanguageModelManager prewarm here: the
        // extension never runs ASR (the host app owns the microphone and
        // the SpeechAnalyzer pipeline), and compiling/caching an LM inside
        // the keyboard's ~60 MB jetsam budget risks the system killing the
        // keyboard outright. The host app prewarms it on session start.
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        installKeyboardHeight()
        configureDictationBehavior()
        installServices()
        installTypingContextProviders()
        installStateActions()
        installSurfaceObservers()
        installSwiftUI()
        _ = configSync.loadPersistedConfig()
        configSync.installDarwinObservers()
        flowCoordinator.refreshSessionState()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flowCoordinator.stopSessionMonitor()
        if state.surface == .typing {
            typingSession.leaveTypingMode()
        }
        if flowCoordinator.preservesLifecycleOnDisappear {
            return
        }
        ExtensionScreenWakeLock.releaseAll()
        flowCoordinator.cancelPipelineUnlessAwaitingResult()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        configureDictationBehavior()
        KeyboardSetupBridge.markExtensionAppearance(hasFullAccess: hasFullAccess)
        state.debugHasFullAccess = hasFullAccess
        flowCoordinator.refreshSessionState()
        flowCoordinator.startSessionMonitor()
        configSync.syncOnboardingStateFromAppGroup()
        configSync.refreshConfigFromAppGroup()
        applyPreferredSurfaceOnOpen()
        if state.surface == .typing {
            typingSession.enterTypingMode()
        }
        configSync.autoAdvancePastKeyboardSetupStepIfNeeded()
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        applyPresentationHeightOffset()
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        disableSystemGestureDelays()
        keyboardHeightConstraint?.constant = targetKeyboardHeight
        refreshReturnKeyRole()
    }

    public override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshReturnKeyRole()
    }

    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    public override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        hosting
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        flowCoordinator.cancelPipelineUnlessAwaitingResult()
        if state.surface == .typing {
            typingSession.leaveTypingMode()
            applySurface(.voice)
        } else {
            typingSession.leaveTypingMode()
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cursorDrag.layoutChrome()
    }

    // MARK: - Services

    private func installServices() {
        textInserter = KeyboardTextInserter(
            state: state,
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            contextBeforeInput: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput },
            scheduleAutoClearError: { [weak self] in self?.scheduleAutoClearError() }
        )

        configSync = KeyboardConfigSync(
            state: state,
            persistor: persistor,
            onFlowSessionChanged: { [weak self] in
                self?.flowCoordinator.refreshSessionState()
            }
        )

        flowCoordinator = KeyboardFlowCoordinator(
            state: state,
            textInserter: textInserter,
            hasFullAccess: { [weak self] in self?.hasFullAccess ?? false },
            wakeLockView: { [weak self] in self?.view },
            openHostApp: { [weak self] path in self?.openHostApp(path: path) },
            detectAndStoreAppContext: { [weak self] in self?.detectAndStoreAppContext() },
            fieldContextProvider: { [weak self] in self?.captureFieldContext() },
            scheduleAutoClearError: { [weak self] in self?.scheduleAutoClearError() },
            refreshConfigFromAppGroup: { [weak self] in self?.configSync.refreshConfigFromAppGroup() }
        )

        cursorDrag = CursorDragController(
            state: state,
            adjustTextPosition: { [weak self] offset in
                self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
            }
        )
    }

    // MARK: - Wiring

    private func installStateActions() {
        state.beginRecording      = { [weak self] in self?.flowCoordinator.pressBegan() }
        state.endRecording        = { [weak self] in self?.flowCoordinator.pressEnded() }
        state.tapMic              = { [weak self] in self?.flowCoordinator.toggleRecording() }
        state.openSettings        = { [weak self] in self?.openHostApp() }
        state.startFlowSession    = { [weak self] in self?.flowCoordinator.beginFlowStart() }
        state.setMode             = { [weak self] m in self?.configSync.persistMode(m) }
        state.setLocale           = { [weak self] l in self?.configSync.persistLocale(l) }
        state.setEngineMode       = { [weak self] m in self?.configSync.persistEngineMode(m) }
        state.setTranslationTargetLocaleId = { [weak self] id in
            self?.configSync.persistTranslationTargetLocaleId(id)
        }
        state.advanceOnboarding   = { [weak self] in self?.configSync.advanceOnboarding() }
        state.completeOnboarding   = { [weak self] in self?.configSync.completeOnboarding() }
        state.requestMicPermission   = { [weak self] in self?.requestMicPermissionFromExtension() }
        state.requestSpeechPermission = { [weak self] in self?.requestSpeechPermissionFromExtension() }
        state.openSystemSettings   = { [weak self] in self?.openSystemSettingsFromExtension() }
        state.insertNewline       = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        state.insertSpace         = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        state.deleteBackward      = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        state.moveCursorHorizontal = { [weak self] steps in
            self?.cursorDrag.moveCursorHorizontally(by: steps)
        }
        state.moveCursorVertical = { [weak self] steps in
            self?.cursorDrag.moveCursorVertically(by: steps)
        }
        state.setCursorDragActive = { [weak self] active in
            self?.cursorDrag.setCursorDragActive(active)
        }
        state.setSurface = { [weak self] surface in
            self?.applySurface(surface)
        }
    }

    private func installSurfaceObservers() {
        state.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if self.state.locksTypingSurface, self.state.surface == .typing {
                    self.applySurface(.voice)
                }
            }
            .store(in: &cancellables)

        state.$surface
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshKeyboardHeight()
            }
            .store(in: &cancellables)
    }

    private func applySurface(_ surface: State.Surface) {
        if surface == .typing, state.locksTypingSurface {
            return
        }
        guard state.surface != surface else {
            refreshKeyboardHeight()
            return
        }
        state.surface = surface
        if surface == .voice {
            typingSession.leaveTypingMode()
        }
        refreshKeyboardHeight()
    }

    private func applyPreferredSurfaceOnOpen() {
        let preferredSurface: State.Surface = TypingInputConfiguration.prefersTypingOnOpen()
            ? .typing
            : .voice
        applySurface(preferredSurface)
    }

    private func refreshKeyboardHeight() {
        // `applyPresentationHeightOffset()` is only a one-time presentation
        // primer used before `viewDidAppear`. Reusing it after a surface
        // switch subtracts the system's ~228 pt encapsulated height from the
        // requested typing height and collapses the keyboard to a thin strip.
        // Once presented, update our height constraint directly, matching the
        // final assignment in `viewDidAppear`.
        keyboardHeightConstraint?.constant = targetKeyboardHeight
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func refreshReturnKeyRole() {
        state.returnKeyRole = returnKeyRole(for: textDocumentProxy.returnKeyType ?? .default)
        // Secure fields must not run English autocomplete / autocorrect / learning.
        typingSession.suggestionsEnabled = !(textDocumentProxy.isSecureTextEntry ?? false)
        typingSession.syncAutocapitalization()
    }

    private func installTypingContextProviders() {
        typingSession.precedingTextProvider = { [weak self] in
            self?.textDocumentProxy.documentContextBeforeInput
        }
        typingSession.autocapitalizationModeProvider = { [weak self] in
            Self.typingAutocapitalizationMode(
                for: self?.textDocumentProxy.autocapitalizationType ?? .sentences
            )
        }
    }

    private static func typingAutocapitalizationMode(
        for type: UITextAutocapitalizationType
    ) -> TypingAutocapitalizationMode {
        switch type {
        case .none:
            return .none
        case .words:
            return .words
        case .sentences:
            return .sentences
        case .allCharacters:
            return .allCharacters
        @unknown default:
            return .sentences
        }
    }

    private func returnKeyRole(for returnKeyType: UIReturnKeyType) -> State.ReturnKeyRole {
        switch returnKeyType {
        case .send, .go, .search, .join, .route, .google, .yahoo, .continue, .emergencyCall:
            return .send
        case .default, .next, .done:
            return .newline
        @unknown default:
            return .newline
        }
    }

    // MARK: - System keyboard chrome

    private func configureDictationBehavior() {
        hasDictationKey = true
    }

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

    // MARK: - Permission / settings stubs (v0.3.0)

    private func requestMicPermissionFromExtension() {}

    private func requestSpeechPermissionFromExtension() {}

    private func openSystemSettingsFromExtension() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        HostAppLauncher.open(url: url, from: self) { _ in }
    }

    // MARK: - Layout

    private func installKeyboardHeight() {
        let constraint = view.heightAnchor.constraint(equalToConstant: targetKeyboardHeight)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

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
        let root = KeyboardSurfaceRoot(
            state: state,
            typing: typingSession,
            onInsert: { [weak self] text in
                self?.textDocumentProxy.insertText(text)
            },
            onDeleteBackward: { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            }
        )
        let host = KeyboardHostingController(rootView: root)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.clipsToBounds = false
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
        hosting = host
        cursorDrag.install(on: view)
    }

    // MARK: - App context

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

    private func captureFieldContext() -> FlowFieldContext {
        let isSecure = textDocumentProxy.isSecureTextEntry ?? false
        let preceding = textDocumentProxy.documentContextBeforeInput
        let following = textDocumentProxy.documentContextAfterInput
        let isAvailable = preceding != nil || following != nil
        let isEmpty = isAvailable && (preceding ?? "").isEmpty && (following ?? "").isEmpty

        return FlowFieldContext(
            precedingText: preceding.map { String($0.suffix(600)) },
            followingText: following.map { String($0.prefix(200)) },
            keyboardType: keyboardTypeName(textDocumentProxy.keyboardType ?? .default),
            returnKeyType: returnKeyTypeName(textDocumentProxy.returnKeyType ?? .default),
            isSecureEntry: isSecure,
            isEmptyField: isEmpty,
            isContextAvailable: isAvailable
        )
    }

    private func keyboardTypeName(_ type: UIKeyboardType) -> String {
        switch type {
        case .asciiCapable: return "asciiCapable"
        case .numbersAndPunctuation: return "numbersAndPunctuation"
        case .URL: return "url"
        case .numberPad: return "numberPad"
        case .phonePad: return "phonePad"
        case .namePhonePad: return "namePhonePad"
        case .emailAddress: return "emailAddress"
        case .decimalPad: return "decimalPad"
        case .twitter: return "twitter"
        case .webSearch: return "webSearch"
        case .asciiCapableNumberPad: return "asciiCapableNumberPad"
        case .default: return "default"
        @unknown default: return "default"
        }
    }

    private func returnKeyTypeName(_ type: UIReturnKeyType) -> String {
        switch type {
        case .go: return "go"
        case .google: return "google"
        case .join: return "join"
        case .next: return "next"
        case .route: return "route"
        case .search: return "search"
        case .send: return "send"
        case .yahoo: return "yahoo"
        case .done: return "done"
        case .emergencyCall: return "emergencyCall"
        case .continue: return "continue"
        case .default: return "default"
        @unknown default: return "default"
        }
    }

    // MARK: - Open host app

    private func openHostApp(path: String = "settings") {
        guard hasFullAccess else {
            let msg = ExtL10n.string("keyboard.error.fullAccessForJump")
            state.phase = .error(.manualOpenRequired, message: msg)
            scheduleAutoClearError()
            return
        }
        guard let url = URL(string: "osgkeyboard://\(path)") else {
            flowCoordinator.handleHostAppOpenResult(path: path, success: false)
            return
        }
        HostAppLauncher.open(url: url, from: self) { [weak self] success in
            self?.flowCoordinator.handleHostAppOpenResult(path: path, success: success)
        }
    }

    private func scheduleAutoClearError() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self else { return }
            switch self.state.phase {
            case .error:
                self.state.phase = .idle
                // Re-derive mic availability right away so a now-ready host
                // turns the mic green immediately instead of lingering orange
                // until the next monitor tick.
                self.flowCoordinator.refreshSessionState()
            default:
                break
            }
        }
    }
}
