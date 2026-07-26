// KeyboardFlowHostHandoff.swift
// OSGKeyboard · Shared
//
// Cold-start / host-ready handoff helpers extracted from KeyboardFlowCoordinator.

import Foundation

public enum KeyboardFlowHostHandoff {
    /// Whether the host ready snapshot can supply a session id for recording.
    public static func resolvedSessionId(defaults: UserDefaults? = nil) -> UUID? {
        FlowSessionBridge.readySnapshot(defaults: defaults)?.sessionId
    }

    /// Manual-open hint copy for a failed host jump.
    public static func manualOpenMessage(
        path: String,
        hasFullAccess: Bool,
        string: (String) -> String
    ) -> String {
        if !hasFullAccess {
            return string("keyboard.error.fullAccessForJump")
        }
        if path == "settings" {
            return string("keyboard.error.manualOpenSettings")
        }
        if path == "startflow" {
            return string("keyboard.error.manualOpenForFlow")
        }
        return string("keyboard.error.manualOpenSettings")
    }
}
