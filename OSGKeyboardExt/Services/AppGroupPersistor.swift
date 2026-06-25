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
        state.localASRBackend  = store.localASRBackend
        // v0.2.1: translation toggle + target locale. Read once at
        // hydration; `refreshRuntimeFlags` keeps them in sync while the
        // keyboard stays open so a Settings change shows up without a
        // re-present cycle.
        state.translationEnabled = store.translationEnabled
        state.translationTargetLocaleId = store.translationTargetLocaleId
        // v0.2.0: iOS `SpeechAnalyzer` is always ready; mirror that
        // into the State flags so downstream consumers see the same
        // shape they did when the previous Qwen3 stack reported "ready".
        state.localModelsReady = true
        state.localModelsLoaded = false

        #if DEBUG
        // Print a masked view of the live App Group config so we can see
        // from the device console exactly what the keyboard extension
        // actually sees (and whether it agrees with the main App).
        let key = store.apiKey
        let masked: String
        if key.count > 8 {
            masked = "\(key.prefix(4))…\(key.suffix(4)) (\(key.count) chars)"
        } else if key.isEmpty {
            masked = "<empty>"
        } else {
            masked = "<\(key.count) chars>"
        }
        print("""
        🔍 [AppGroupPersistor.load]
           providerId      = \(store.providerId)
           baseURL         = \(store.baseURL)
           apiKey          = \(masked)
           model           = \(store.model)
           modeId          = \(store.modeId)
           localeId        = \(store.localeId)
           localASRBackend = \(store.localASRBackend.rawValue)
        """)
        #endif
        return .loaded
    }

    /// Lightweight refresh for flags the host app may update while the
    /// keyboard stays open (model downloads, engine switches).
    public func refreshRuntimeFlags(into state: KeyboardViewController.State) {
        guard AppGroup.isAvailable else { return }
        let store = AppGroupStore()
        state.engineMode = store.engineMode
        state.localASRBackend = store.localASRBackend
        // v0.2.1: keep translation state in sync with the host app so the
        // chip on the keyboard reflects the latest value without a re-
        // present cycle.
        state.translationEnabled = store.translationEnabled
        state.translationTargetLocaleId = store.translationTargetLocaleId
        // v0.2.0: iOS `SpeechAnalyzer` is always ready. Keep these
        // toggles here so the keyboard UI doesn't flicker if the host
        // app briefly clears them while refactoring.
        state.localModelsReady = true
        state.localModelsLoaded = false
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

    /// Persist `localASRBackend` to the App Group store.
    public func persist(localASRBackend: LocalASRBackend) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setLocalASRBackend(localASRBackend)
    }

    /// v0.2.1: persist translation toggle. Wired through the
    /// `KeyboardViewController.setTranslation` action hook.
    public func persist(translationEnabled: Bool) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setTranslationEnabled(translationEnabled)
    }

    /// v0.2.1: persist translation target locale id (e.g. `"en"`).
    public func persist(translationTargetLocaleId: String) {
        guard AppGroup.isAvailable else { return }
        AppGroupStore().setTranslationTargetLocaleId(translationTargetLocaleId)
    }
}