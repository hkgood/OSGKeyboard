// AppGroupStore+ConfigurationStore.swift
// OSGKeyboard · Shared
//
// iOS / keyboard-extension configuration backed by the App Group suite.

import Foundation

extension AppGroupStore: ConfigurationStore {
    public var cloudASRPersistence: UserDefaults { defaults }
}
