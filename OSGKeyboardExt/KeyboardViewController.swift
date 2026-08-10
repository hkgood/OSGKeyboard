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
    /// Created on first typing use so the default voice surface never pays
    /// for `TypingSessionController` / engine factories at KVC init.
    private var typingSessionStorage: TypingSessionController?
    private var typingSession: TypingSessionController {
        if let typingSessionStorage { return typingSessionStorage }
        let created = TypingSessionController()
        typingSessionStorage = created
        return created
    }
    private let persistor = AppGroupPersistor()

    private var hosting: UIHostingController<KeyboardSurfaceRoot>?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var systemEncapsulatedHeight: CGFloat = 228
    /// Presentation height priming is only valid during the slide-in. After
    /// `viewDidAppear` we must keep the constraint at `target` — re-applying
    /// the offset (or letting a paste alert interrupt the appear sequence)
    /// makes the slot land at `target + encapsulated` and floats the chrome.
    private enum HeightPresentationPhase {
        case idle
        case priming
        case presented
    }
    private var heightPhase: HeightPresentationPhase = .idle
    private var cancellables = Set<AnyCancellable>()

    private var textInserter: KeyboardTextInserter!
    private var flowCoordinator: KeyboardFlowCoordinator!
    private var lastInputEditCoordinator: LastInputEditCoordinator!
    private var configSync: KeyboardConfigSync!
    /// UIKit may synchronously lay out the view during `viewDidLoad`.
    /// Keep this optional so an early layout pass is harmless.
    private var cursorDrag: CursorDragController?

    /// iPad-scale keys require both an iPad host and regular horizontal space.
    /// This keeps compact iPad multitasking on phone metrics and prevents wide
    /// iPhones from being mistaken for iPads.
    private var isIPadLayout: Bool {
        KeyboardChromeLayout.usesIPadMetrics(
            isPad: UIDevice.current.userInterfaceIdiom == .pad,
            hasRegularWidth: traitCollection.horizontalSizeClass == .regular
        )
    }

    /// Width the layout should be sized against. `view.bounds` is empty before
    /// the first layout pass, so fall back to the screen the keyboard is on.
    private var currentLayoutWidth: CGFloat {
        let width = view.bounds.width
        guard width > 0 else {
            return (view.window?.windowScene?.screen ?? UIScreen.main).bounds.width
        }
        return width
    }

    private var targetKeyboardHeight: CGFloat {
        KeyboardSurfaceRoot.height(
            for: state.surface,
            isIPad: state.usesIPadLayoutMetrics,
            width: state.layoutWidth
        )
    }

    // MARK: - Init

    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        OSGDiag.log("KVC.init(nib) begin \(OSGDiag.memoryTag())", category: "boot")
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        OSGDiag.log("KVC.init(nib) done \(OSGDiag.memoryTag())", category: "boot")
    }

    public required init?(coder: NSCoder) {
        OSGDiag.log("KVC.init(coder) begin \(OSGDiag.memoryTag())", category: "boot")
        super.init(coder: coder)
        OSGDiag.log("KVC.init(coder) done \(OSGDiag.memoryTag())", category: "boot")
    }

    deinit {
        // Intentionally NSLog-only: deinit is nonisolated.
        NSLog("%@", "[OSGDiag/boot] KVC.deinit")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        state.showsSystemGlobeKey = UIDevice.current.userInterfaceIdiom == .pad
        // Voice-first keyboard — hide the misleading "English" subtitle in Settings.
        primaryLanguage = "mis"
        let preferred = TypingInputConfiguration.preferredSurfaceOnOpen()
        OSGDiag.log(
            "KVC.viewDidLoad begin preferredSurface=\(preferred.rawValue) "
                + "fullAccess=\(hasFullAccess) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        // Deliberately NO CustomLanguageModelManager prewarm here: the
        // extension never runs ASR (the host app owns the microphone and
        // the SpeechAnalyzer pipeline), and compiling/caching an LM inside
        // the keyboard's ~60 MB jetsam budget risks the system killing the
        // keyboard outright. The host app prewarms it on session start.
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        // Establish layout dependencies before applying the preferred surface.
        // `applySurface` updates height and UIKit may lay out synchronously.
        refreshLayoutMode()
        installKeyboardHeight()
        configureDictationBehavior()
        installServices()
        OSGDiag.log("KVC.viewDidLoad after installServices \(OSGDiag.memoryTag())", category: "boot")
        // Apply open preference before mounting SwiftUI so the first frame is
        // already voice or typing — avoids a visible surface flash.
        applyPreferredSurfaceOnOpen()
        OSGDiag.log("KVC.viewDidLoad after preferredSurface surface=\(state.surface.rawValue)", category: "boot")
        installTypingContextProviders()
        installStateActions()
        installSurfaceObservers()
        installSwiftUI()
        OSGDiag.log("KVC.viewDidLoad after installSwiftUI \(OSGDiag.memoryTag())", category: "boot")
        _ = configSync.loadPersistedConfig()
        configSync.installDarwinObservers()
        flowCoordinator.refreshSessionState()
        OSGDiag.log(
            "KVC.viewDidLoad done surface=\(state.surface.rawValue) "
                + "sessionActive=\(FlowSessionBridge.isSessionActive()) "
                + "hostReady=\(FlowSessionBridge.isHostReady()) \(OSGDiag.memoryTag())",
            category: "boot"
        )
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        OSGDiag.log(
            "KVC.viewWillDisappear surface=\(state.surface.rawValue) "
                + "preserve=\(flowCoordinator.preservesLifecycleOnDisappear) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        heightPhase = .idle
        flowCoordinator.stopSessionMonitor()
        // Remember what the user left on, then pre-position a reused
        // extension instance for the next open policy (no first-frame jump).
        let preserve = flowCoordinator.preservesLifecycleOnDisappear
        TypingInputConfiguration.persistLastSurface(
            preserve ? .voice : state.surface
        )
        if !preserve {
            prepareSurfaceForNextPresentation()
        }
        if state.surface == .typing {
            typingSession.leaveTypingMode()
        }
        if preserve {
            return
        }
        ExtensionScreenWakeLock.releaseAll()
        flowCoordinator.cancelPipelineUnlessAwaitingResult()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        OSGDiag.log(
            "KVC.viewWillAppear begin surface=\(state.surface.rawValue) "
                + "fullAccess=\(hasFullAccess) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        configureDictationBehavior()
        KeyboardSetupBridge.markExtensionAppearance(hasFullAccess: hasFullAccess)
        state.debugHasFullAccess = hasFullAccess
        // Refresh only Flow/config state; edit targets come from verified OSG insertions.
        flowCoordinator.refreshSessionState()
        flowCoordinator.startSessionMonitor()
        configSync.syncOnboardingStateFromAppGroup()
        configSync.refreshConfigFromAppGroup()
        // Settings may have changed while the extension stayed alive.
        applyPreferredSurfaceOnOpen()
        // Re-warm Taptic after host app switches: SwiftUI `onAppear` often
        // skips when the extension process is reused, leaving generators cold.
        KeyboardHapticFeedback.prepare()
        if state.surface == .typing {
            OSGDiag.log("KVC.viewWillAppear enterTypingMode", category: "boot")
            typingSession.enterTypingMode()
        }
        OSGDiag.log(
            "KVC.viewWillAppear done surface=\(state.surface.rawValue) \(OSGDiag.memoryTag())",
            category: "boot"
        )
    }

    public override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        if heightPhase == .presented {
            // Spurious re-appear while already on screen (e.g. system alert
            // lifecycle noise) — never re-run the offset trick.
            lockPresentedKeyboardHeight()
        } else {
            heightPhase = .priming
            applyPresentationHeightOffset()
        }
        OSGDiag.log(
            "KVC.viewIsAppearing phase=\(heightPhaseLog) "
                + "height=\(keyboardHeightConstraint?.constant ?? -1) "
                + "\(OSGDiag.memoryTag())",
            category: "boot"
        )
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        OSGDiag.log(
            "KVC.viewDidAppear begin surface=\(state.surface.rawValue) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        disableSystemGestureDelays()
        heightPhase = .presented
        lockPresentedKeyboardHeight()
        refreshReturnKeyRole()
        // Presentation math is locked before arming the PiP handoff.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.heightPhase == .presented else { return }
            self.flowCoordinator.ensurePiPReadyOnKeyboardOpen()
        }
        OSGDiag.log(
            "KVC.viewDidAppear done height=\(targetKeyboardHeight) \(OSGDiag.memoryTag())",
            category: "boot"
        )
    }

    public override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshReturnKeyRole()
        textInserter?.refreshEditingAvailability()
        lastInputEditCoordinator?.refreshContext()
    }

    public override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        textInserter?.refreshEditingAvailability()
        lastInputEditCoordinator?.refreshContext()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass else {
            return
        }
        refreshLayoutMode()
    }

    public override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        [.left, .right]
    }

    public override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        hosting
    }

    public override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        OSGDiag.log(
            "KVC.didReceiveMemoryWarning surface=\(state.surface.rawValue) \(OSGDiag.memoryTag())",
            category: "boot"
        )
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
        // Rotation does not change `horizontalSizeClass` on iPad (both
        // orientations are regular), so this is the only callback that sees a
        // portrait→landscape resize. `refreshLayoutMode` no-ops unless the
        // layout bucket actually changed, so this cannot loop.
        refreshLayoutMode()
        cursorDrag?.layoutChrome()
        enforcePresentedKeyboardHeightIfNeeded()
    }

    // MARK: - Services

    private func installServices() {
        textInserter = KeyboardTextInserter(
            state: state,
            insertText: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            deleteBackward: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            contextBeforeInput: { [weak self] in self?.textDocumentProxy.documentContextBeforeInput },
            fieldContextProvider: { [weak self] in self?.captureFieldContext() },
            selectedText: { [weak self] in self?.textDocumentProxy.selectedText },
            scheduleAutoClearError: { [weak self] in self?.scheduleAutoClearError() }
        )

        configSync = KeyboardConfigSync(
            state: state,
            persistor: persistor,
            onFlowSessionChanged: { [weak self] in
                self?.flowCoordinator.refreshSessionState()
            },
            onConfigChanged: { [weak self] in
                // Only an already-live typing session can be showing the setup
                // error; never force-create one just to retry.
                self?.typingSessionStorage?.retryPrepareAfterResourceDeployment()
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
        lastInputEditCoordinator = LastInputEditCoordinator(
            state: state,
            textInserter: textInserter,
            beginFlow: { [weak self] reference in
                self?.flowCoordinator.beginEditRecording(reference: reference)
                    ?? .rejected(.hostUnavailable)
            },
            stopFlow: { [weak self] in self?.flowCoordinator.stopEditRecording() },
            abortFlow: { [weak self] in self?.flowCoordinator.abortEditRecording() },
            acknowledge: { [weak self] outcome in
                self?.flowCoordinator.acknowledgeEditResult(outcome)
            }
        )
        flowCoordinator.onEditHostRecordingConfirmed = { [weak self] in
            self?.lastInputEditCoordinator.hostRecordingConfirmed()
        }
        flowCoordinator.onEditResult = { [weak self] result in
            self?.lastInputEditCoordinator.receive(result: result)
        }
        flowCoordinator.onEditFailure = { [weak self] message in
            self?.lastInputEditCoordinator.fail(message)
        }
        _ = textInserter.recoverPendingEditTransactionIfNeeded()

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
        state.setMicTouchActive   = { [weak self] active in
            self?.flowCoordinator.setMicTouchActive(active)
        }
        state.cancelVoiceInput = { [weak self] in
            self?.flowCoordinator.cancelCurrentDictation()
        }
        state.beginEditLastInput = { [weak self] in
            self?.lastInputEditCoordinator.begin()
        }
        state.stopEditListening = { [weak self] in
            self?.lastInputEditCoordinator.stopListening()
        }
        state.confirmEditResult = { [weak self] in
            self?.lastInputEditCoordinator.confirm()
        }
        state.closeEditMode = { [weak self] in
            self?.lastInputEditCoordinator.close()
        }
        state.openSettings        = { [weak self] in self?.openHostApp() }
        state.openInputMethodSetup = { [weak self] in self?.openHostApp(path: "deployrime") }
        // The globe UIButton registers this controller's standard
        // `handleInputModeList(from:with:)` action for all touch events.
        state.inputModeController = self
        state.startFlowSession    = { [weak self] in self?.flowCoordinator.beginFlowStart() }
        state.setMode             = { [weak self] m in self?.configSync.persistMode(m) }
        state.setLocale           = { [weak self] l in self?.configSync.persistLocale(l) }
        state.setEngineMode       = { [weak self] m in self?.configSync.persistEngineMode(m) }
        state.setTranslationTargetLocaleId = { [weak self] id in
            self?.configSync.persistTranslationTargetLocaleId(id)
        }
        state.insertNewline       = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        state.insertSpace         = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        state.deleteBackward      = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        state.undoLastInsertion   = { [weak self] in self?.textInserter.undoLastInsertion() }
        state.redoLastInsertion   = { [weak self] in self?.textInserter.redoLastInsertion() }
        state.copySelection       = { [weak self] in self?.textInserter.copySelection() }
        state.cutSelection        = { [weak self] in self?.textInserter.cutSelection() }
        state.moveCursorHorizontal = { [weak self] steps in
            self?.cursorDrag?.moveCursorHorizontally(by: steps)
        }
        state.moveCursorVertical = { [weak self] steps in
            self?.cursorDrag?.moveCursorVertically(by: steps)
        }
        state.setCursorDragActive = { [weak self] active in
            self?.cursorDrag?.setCursorDragActive(active)
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
            OSGDiag.log("applySurface blocked typing (locksTypingSurface)", category: "boot")
            return
        }
        if surface == .typing, FlowSessionBridge.isHostHeavy() {
            OSGDiag.log("applySurface stay voice hostHeavy=1", category: "boot")
            return
        }
        guard state.surface != surface else {
            refreshKeyboardHeight()
            return
        }
        OSGDiag.log(
            "applySurface \(state.surface.rawValue) → \(surface.rawValue) \(OSGDiag.memoryTag())",
            category: "boot"
        )
        state.surface = surface
        if surface == .voice {
            typingSession.leaveTypingMode()
        } else {
            typingSession.enterTypingMode()
        }
        refreshKeyboardHeight()
    }

    private func applyPreferredSurfaceOnOpen() {
        let preferred = TypingInputConfiguration.preferredSurfaceOnOpen()
        let resolved = KeyboardOpenSurfacePolicy.resolve(
            locksTypingSurface: state.locksTypingSurface,
            preferred: preferred
        )
        OSGDiag.log(
            "applyPreferredSurfaceOnOpen preferred=\(preferred.rawValue) "
                + "resolved=\(resolved.rawValue) "
                + "locksTyping=\(state.locksTypingSurface ? 1 : 0)",
            category: "boot"
        )
        applySurface(resolved)
    }

    /// When not remembering, snap to the static open preference while hidden
    /// so a reused keyboard instance does not animate voice → typing on show.
    private func prepareSurfaceForNextPresentation() {
        guard !TypingInputConfiguration.remembersLastSurface() else { return }
        let preferred = TypingInputConfiguration.preferredSurfaceOnOpen()
        guard state.surface != preferred else { return }
        state.surface = preferred
    }

    private func refreshKeyboardHeight() {
        // `applyPresentationHeightOffset()` is only a one-time presentation
        // primer used before `viewDidAppear`. Reusing it after a surface
        // switch subtracts the system's ~228 pt encapsulated height from the
        // requested typing height and collapses the keyboard to a thin strip.
        // Once presented, update our height constraint directly, matching the
        // final assignment in `viewDidAppear`. Avoid synchronous layout here:
        // this is also called during `viewDidLoad`, where re-entrant layout can
        // observe partially initialized controller dependencies.
        if heightPhase == .presented {
            lockPresentedKeyboardHeight()
        } else {
            keyboardHeightConstraint?.constant = targetKeyboardHeight
            view.setNeedsLayout()
        }
    }

    private func refreshLayoutMode() {
        let usesIPadMetrics = isIPadLayout
        let width = currentLayoutWidth
        // `state.layoutWidth` tracks the width that last changed the layout
        // bucket, not every intermediate width: republishing on each frame of
        // a Stage Manager drag would rebuild the SwiftUI grid continuously.
        let bucketChanged = KeyboardChromeLayout.usesWideIPadMetrics(
            isIPad: usesIPadMetrics,
            width: width
        ) != KeyboardChromeLayout.usesWideIPadMetrics(
            isIPad: state.usesIPadLayoutMetrics,
            width: state.layoutWidth
        )
        guard state.usesIPadLayoutMetrics != usesIPadMetrics || bucketChanged else { return }
        state.usesIPadLayoutMetrics = usesIPadMetrics
        state.layoutWidth = width
        refreshKeyboardHeight()
    }

    private var heightPhaseLog: String {
        switch heightPhase {
        case .idle: return "idle"
        case .priming: return "priming"
        case .presented: return "presented"
        }
    }

    private func lockPresentedKeyboardHeight() {
        keyboardHeightConstraint?.constant = targetKeyboardHeight
        view.setNeedsLayout()
    }

    /// After presentation, the constraint must stay at `target`. Spurious
    /// lifecycle noise must not leave us primed at `target − encapsulated`.
    private func enforcePresentedKeyboardHeightIfNeeded() {
        guard heightPhase == .presented else { return }
        let target = targetKeyboardHeight
        guard let constraint = keyboardHeightConstraint else { return }
        let was = constraint.constant
        guard abs(was - target) > 0.5 else { return }
        constraint.constant = target
        OSGDiag.log(
            "KVC.heightEnforce constraint \(Int(was))→\(Int(target))",
            category: "boot"
        )
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

    /// Only walk our own input-view subtree. Recursing into the host window /
    /// root VC previously risked "System gesture gate timed out" and the
    /// system killing the keyboard plugin.
    private func disableSystemGestureDelays() {
        disableGestureDelays(in: view)
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

    // MARK: - Layout

    private func installKeyboardHeight() {
        let constraint = view.heightAnchor.constraint(equalToConstant: targetKeyboardHeight)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        keyboardHeightConstraint = constraint
    }

    private func applyPresentationHeightOffset() {
        // Only valid while priming the slide-in. Callers must not invoke this
        // after `heightPhase == .presented`.
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
        cursorDrag?.install(on: view)
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
