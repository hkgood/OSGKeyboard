// KeyboardOpenSurfacePolicy.swift
// OSGKeyboard · Shared
//
// Pure open-surface decision used by the keyboard extension.

import Foundation

public enum KeyboardOpenSurfacePolicy: Sendable {
    /// Surface to show on the first frame of a keyboard presentation.
    public static func resolve(
        locksTypingSurface: Bool,
        preferred: KeyboardState.Surface
    ) -> KeyboardState.Surface {
        if locksTypingSurface {
            return .voice
        }
        return preferred
    }
}
