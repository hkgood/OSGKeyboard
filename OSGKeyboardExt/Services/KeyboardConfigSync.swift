// KeyboardConfigSync.swift
// OSGKeyboard · Keyboard Extension
//
// App Group config hydration, Darwin observers, and onboarding-complete
// mirroring (mic gate only — full setup lives in the host app).

import Foundation
import OSGKeyboardShared

@MainActor
final class KeyboardConfigSync {
    private let state: KeyboardState
    private let persistor: AppGroupPersistor
    private let onFlowSessionChanged: () -> Void
    /// Fired on every App Group config change — the host posts one after a
    /// successful Rime deployment, which is the keyboard's only signal that
    /// typing resources just became available.
    private let onConfigChanged: () -> Void

    /// Grace period after a chip-side translation write during which the
    /// 1 Hz App Group poll must not overwrite `translationTargetLocaleId`.
    var translationConfigProtectedUntil: Date?

    private var flowSessionDarwinObserver: FlowSessionDarwinObserver?
    private var transcriptionDarwinObserver: FlowSessionDarwinObserver?
    private var hostReadyDarwinObserver: FlowSessionDarwinObserver?
    private var configDarwinObserver: FlowSessionDarwinObserver?

    init(
        state: KeyboardState,
        persistor: AppGroupPersistor,
        onFlowSessionChanged: @escaping () -> Void,
        onConfigChanged: @escaping () -> Void = {}
    ) {
        self.state = state
        self.persistor = persistor
        self.onFlowSessionChanged = onFlowSessionChanged
        self.onConfigChanged = onConfigChanged
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
        hostReadyDarwinObserver = FlowSessionDarwinObserver(
            notificationName: FlowSessionDarwin.hostReadyNotificationName
        ) { [weak self] in
            self?.onFlowSessionChanged()
        }
        configDarwinObserver = FlowSessionDarwinObserver(
            notificationName: AppGroupConfigDarwin.notificationName
        ) { [weak self] in
            guard let self else { return }
            self.refreshConfigFromAppGroup()
            self.onConfigChanged()
        }
    }

    func loadPersistedConfig() -> AppGroupLoadResult {
        switch persistor.load(into: state) {
        case .loaded:
            OSGLog.keyboardExt.info("config loaded")
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
        // Host may complete (or reset) onboarding while the extension stays alive.
        syncOnboardingStateFromAppGroup()
    }

    /// Mirrors host-app onboarding completion for the mic gate only.
    /// Does not sync `onboardingPage` — page flow is host-app exclusive.
    func syncOnboardingStateFromAppGroup() {
        let store = AppGroupStore()
        // Keychain fallback: a reboot must not resurrect the mic gate when
        // App Group transiently reads empty.
        state.hasCompletedOnboarding = store.hasCompletedOnboarding || Keychain.hasCompletedOnboarding()
        state.isOnboardingPracticeActive = KeyboardSetupBridge.isOnboardingPracticeActive
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
        translationConfigProtectedUntil = KeyboardTranslationConfigProtection.protectionDeadline()
        persistor.persist(translationTargetLocaleId: resolved)
    }

    func persistMode(_ mode: KeyboardState.InputMode) {
        state.mode = mode
        persistor.persist(mode: mode)
    }
}
