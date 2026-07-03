// ScreenWakeLock.swift
// OSGKeyboard · Main App
//
// Reference-counted idle-timer disable for Flow session ownership.

import UIKit

@MainActor
enum ScreenWakeLock {
    private static var holdCount = 0

    static func acquire() {
        holdCount += 1
        if holdCount == 1 {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    static func release() {
        guard holdCount > 0 else { return }
        holdCount -= 1
        if holdCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
