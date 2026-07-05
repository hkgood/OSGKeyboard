// KeyboardConfigSync.swift
// OSGKeyboard · Keyboard Extension
//
// App Group config hydration, Darwin observers, and onboarding mirroring.

import Foundation
import OSGKeyboardShared

@MainActor
final class KeyboardConfigSync {
    private let state: KeyboardState
    private let persistor: AppGroupPersistor
    private let onFlowSessionChanged: () -> Void

    /// Grace period after a chip-side translation write during which the
    /// 1 Hz App Group poll must not overwrite `translationTargetLocaleId`.
    var translationConfigProtectedUntil: Date?

    private var flowSessionDarwinObserver: FlowSessionDarwinObserver?
    private var transcriptionDarwinObserver: FlowSessionDarwinObserver?
    private var configDarwinObserver: FlowSessionDarwinObserver?

    init(
        state: KeyboardState,
        persistor: AppGroupPersistor,
        onFlowSessionChanged: @escaping () -> Void
    ) {
        self.state = state
        self.persistor = persistor
        self.onFlowSessionChanged = onFlowSessionChanged
    }

    func installDarwinObservers() {
        flowSessionDarwinObserver = FlowSessionDarwinObserver { [weak self] in
            self?.onFlowSessionChanged()
        }
        transcriptionDarwinObserver = FlowSessionDarwinObserver(
            notificationName: FlowSessionDarwin.transcriptionNotificationName
        ) { [weak self] in
            self?.onFlowSessionChanged()
        }
        configDarwinObserver = FlowSessionDarwinObserver(
            notificationName: AppGroupConfigDarwin.notificationName
        ) { [weak self] in
            self?.refreshConfigFromAppGroup()
        }
    }

    func loadPersistedConfig() -> AppGroupLoadResult {
        switch persistor.load(into: state) {
        case .loaded:
            OSGLog.keyboardExt.info(
                "config loaded — cursorDragNavigationEnabled=\(self.state.cursorDragNavigationEnabled)"
            )
            syncOnboardingStateFromAppGroup()
            return .loaded
        case .unavailable:
            state.phase = .error(
                .appGroupUnavailable,
                message: ExtL10n.string("keyboard.error.appGroupUnavailable")
            )
            return .unavailable
        }
    }

    func refreshConfigFromAppGroup() {
        persistor.refreshRuntimeFlags(
            into: state,
            protectTranslationUntil: translationConfigProtectedUntil
        )
    }

    func syncOnboardingStateFromAppGroup() {
        let store = AppGroupStore()
        state.hasCompletedOnboarding = store.hasCompletedOnboarding
        state.onboardingPage = store.onboardingPage
    }

    func autoAdvancePastKeyboardSetupStepIfNeeded() {
        guard !state.hasCompletedOnboarding else { return }
        guard state.onboardingPage == 3 else { return }
        guard KeyboardSetupBridge.isReadyForOnboardingSkip else { return }
        let store = AppGroupStore()
        store.setOnboardingPage(4)
        state.onboardingPage = 4
    }

    func advanceOnboarding() {
        let store = AppGroupStore()
        let nextPage = min(4, store.onboardingPage + 1)
        store.setOnboardingPage(nextPage)
        state.onboardingPage = nextPage
    }

    func completeOnboarding() {
        let store = AppGroupStore()
        store.setHasCompletedOnboarding(true)
        store.setOnboardingPage(4)
        state.hasCompletedOnboarding = true
        state.onboardingPage = 4
    }

    func persistLocale(_ id: String) {
        state.localeId = id
        persistor.persist(localeId: id)
    }

    func persistEngineMode(_ mode: String) {
        state.engineMode = mode
        persistor.persist(engineMode: mode)
    }

    func persistTranslationTargetLocaleId(_ id: String) {
        let resolved = TranslationLanguageCatalog.resolve(id).id
        state.translationTargetLocaleId = resolved
        translationConfigProtectedUntil = Date().addingTimeInterval(2.5)
        persistor.persist(translationTargetLocaleId: resolved)
    }

    func persistMode(_ mode: KeyboardState.InputMode) {
        state.mode = mode
        persistor.persist(mode: mode)
    }
}
