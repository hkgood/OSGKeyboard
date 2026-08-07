// KeyboardOpenSurfacePolicy.swift
// OSGKeyboard · Shared
//
// Pure open-surface decision used by the keyboard extension. Extracted so
// paste-alert sticky resume can be unit-tested without UIKit.

import Foundation

public enum KeyboardOpenSurfacePolicy: Sendable {
    /// Surface to show on the first frame of a keyboard presentation.
    public static func resolve(
        locksTypingSurface: Bool,
        clipboardCommandActive: Bool,
        stickyPreferVoice: Bool,
        preferred: KeyboardState.Surface
    ) -> KeyboardState.Surface {
        if locksTypingSurface || clipboardCommandActive || stickyPreferVoice {
            return .voice
        }
        return preferred
    }
}
