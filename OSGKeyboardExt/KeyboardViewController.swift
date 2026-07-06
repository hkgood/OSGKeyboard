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
import OSGKeyboardShared

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
    public typealias State = KeyboardState

    private let state = State()
    private let persistor = AppGroupPersistor()

    private var hosting: UIHostingController<KeyboardRootView>?
    private var keyboardHeightConstraint: NSLayoutConstraint?
    private var systemEncapsulatedHeight: CGFloat = 228

    private var textInserter: KeyboardTextInserter!
    private var flowCoordinator: KeyboardFlowCoordinator!
    private var configSync: KeyboardConfigSync!
    private var cursorDrag: CursorDragController!

    private var targetKeyboardHeight: CGFloat {
        KeyboardRootView.totalHeight
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        // Voice-first keyboard — hide the misleading "English" subtitle in Settings.
        primaryLanguage = "mis"
        OSGLog.keyboardExt.info("viewDidLoad — extension booted")
        CustomLanguageModelManager.shared.prepareInBackgroundIfNeeded()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
        installKeyboardHeight()
        configureDictationBehavior()
        installServices()
        installStateActions()
        installSwiftUI()
        _ = configSync.loadPersistedConfig()
        configSync.installDarwinObservers()
        flowCoordinator.refreshSessionState()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flowCoordinator.stopSessionMonitor()
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
        flowCoordinator.refreshSessionState()
        flowCoordinator.startSessionMonitor()
        configSync.syncOnboardingStateFromAppGroup()
        configSync.refreshConfigFromAppGroup()
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
        let root = KeyboardRootView(state: state)
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
            default:
                break
            }
        }
    }
}
