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
        state.localeId = store.localeId
        state.mode = KeyboardViewController.State.InputMode(rawValue: store.modeId) ?? .polish

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
           providerId = \(store.providerId)
           baseURL    = \(store.baseURL)
           apiKey     = \(masked)
           model      = \(store.model)
           modeId     = \(store.modeId)
           localeId   = \(store.localeId)
        """)
        #endif
        return .loaded
    }

    /// Persist `mode` to the App Group store.
    public func persist(mode: KeyboardViewController.State.InputMode) {
        AppGroupStore().setModeId(mode.rawValue)
    }

    /// Persist `localeId` to the App Group store.
    public func persist(localeId: String) {
        AppGroupStore().setLocaleId(localeId)
    }
}