// AppGroupPersistor.swift
// OSGKeyboard · Keyboard Extension
//
// Extracted from KeyboardViewController so the view controller doesn't
// have to know about App Group availability checks, AppGroupStore
// reads/writes, or how to render the locale / mode into the State
// view model.

import Foundation
import OSGKeyboardShared

/// Outcome of `load()` — distinguishes "everything fine" from "the
/// App Group isn't configured so we can't read anything". The view
/// controller flips its `phase` accordingly.
public enum AppGroupLoadResult: Equatable {
    case loaded
    case unavailable
}

@MainActor
public struct AppGroupPersistor {

    public init() {}

    /// Hydrate `state` from the App Group. Returns `loaded` on success
    /// or `unavailable` if the App Group suite can't be opened (which
    /// in DEBUG `fatalError`s inside `AppGroup.isAvailable`).
    public func load(into state: KeyboardViewController.State) -> AppGroupLoadResult {
        guard AppGroup.isAvailable else {
            return .unavailable
        }
        let store = AppGroupStore()
        state.localeId         = store.localeId
        // Both engines always polish; ignore legacy off/transcribe modeId.
        state.mode             = .polish
        state.engineMode       = store.engineMode
        // Only the target locale is persisted;
        // `translationEnabled` is derived from it. Hydrate once at
        // startup; `refreshRuntimeFlags` keeps the chip in sync while
        // the keyboard stays open.
        state.translationTargetLocaleId = store.translationTargetLocaleId
        state.handednessPreference = store.handednessPreference
        state.clipboardHistoryEnabled = store.clipboardHistoryEnabled
        state.clipboardCandidateBarEnabled = store.clipboardCandidateBarEnabled
        state.enabledClipboardSkillIDs = store.agentSkillLayout.enabledIDs
        state.keyboardHapticIntensity = store.keyboardHapticIntensity
        applyAPIKeyAvailability(store: store, into: state)

        #if DEBUG
        // Log only credential availability and the base URL origin. Never put
        // credential fragments or URL path/query/userinfo into device logs.
        let credentialStatus: String
        switch Keychain.apiKeyOutcome(for: store.providerId, preferICloudSync: true) {
        case .found(let value):
            credentialStatus = value.isEmpty ? "empty" : "configured"
        case .notFound:
            credentialStatus = store.apiKey.isEmpty ? "empty" : "configured"
        case .unavailable:
            credentialStatus = "keychainUnavailable"
        }
        let components = URLComponents(string: store.baseURL)
        let baseURLOrigin = components?.scheme.flatMap { scheme in
            components?.host.map { host in "\(scheme)://\(host)" }
        } ?? "<invalid>"
        print("""
        🔍 [AppGroupPersistor.load]
           providerId      = \(store.providerId)
           baseURLOrigin   = \(baseURLOrigin)
           credential      = \(credentialStatus)
           model           = \(store.model)
           modeId          = \(store.modeId)
           localeId        = \(store.localeId)
        """)
        #endif
        return .loaded
    }

    /// Lightweight refresh for flags the host app may update while the
    /// keyboard stays open (model downloads, engine switches).
    ///
    /// When `protectTranslationUntil` is in the future, the translation
    /// target locale is not overwritten — avoids the 1 Hz poll clobbering
    /// a chip selection the user just wrote to the App Group.
    public func refreshRuntimeFlags(
        into state: KeyboardViewController.State,
        protectTranslationUntil: Date? = nil
    ) {
        guard AppGroup.isAvailable else { return }
        let store = AppGroupStore()
        state.engineMode = store.engineMode
        let shouldProtectTranslation = KeyboardTranslationConfigProtection.shouldProtect(
            until: protectTranslationUntil
        )
        if !shouldProtectTranslation {
            state.translationTargetLocaleId = store.translationTargetLocaleId
        }
        state.handednessPreference = store.handednessPreference
        state.clipboardHistoryEnabled = store.clipboardHistoryEnabled
        state.clipboardCandidateBarEnabled = store.clipboardCandidateBarEnabled
        state.enabledClipboardSkillIDs = store.agentSkillLayout.enabledIDs
        state.keyboardHapticIntensity = store.keyboardHapticIntensity
        applyAPIKeyAvailability(store: store, into: state)
    }

    /// Cloud without ASR/LLM keys blocks the mic. Local ASR still works when
    /// the polish key is missing — show a soft tip above the mic instead.
    private func applyAPIKeyAvailability(
        store: AppGroupStore,
        into state: KeyboardViewController.State
    ) {
        state.aiServiceAvailable = !store.isPolishKeyMissing
        if store.isCloudAPIKeyMissingForVoiceInput {
            state.micDisabled = true
            state.micDisabledHint = ExtL10n.string("keyboard.mic.disabled.missingApiKey")
        } else if store.isPolishKeyMissing {
            state.micDisabled = false
            state.micDisabledHint = ExtL10n.string("keyboard.mic.hint.missingPolishApiKey")
        } else {
            state.micDisabled = false
            state.micDisabledHint = ""
        }
    }

    /// Persist `mode` to the App Group store.
    public func persist(mode: KeyboardViewController.State.InputMode) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setModeId(mode.rawValue)
    }

    /// Persist `localeId` to the App Group store.
    public func persist(localeId: String) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setLocaleId(localeId)
    }

    /// Persist `engineMode` to the App Group store.
    public func persist(engineMode: String) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setEngineMode(engineMode)
    }

    /// Persist translation target locale id (e.g. `"en"`,
    /// `"ja"`, or `TranslationLanguageCatalog.offLocaleId`). The
    /// chip / picker call this through `KeyboardState.setTranslationTargetLocaleId`.
    ///
    /// There is no `persist(translationEnabled:)` because the
    /// enabled state is derived from the locale id, so callers only
    /// need to write the locale. Keeping the legacy Bool overload
    /// around would have implied that there's a separate on/off
    /// switch to persist, which is no longer the model.
    public func persist(translationTargetLocaleId: String) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setTranslationTargetLocaleId(translationTargetLocaleId)
    }
}
