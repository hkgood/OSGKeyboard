// ExtensionScreenWakeLock.swift
// OSGKeyboard · Keyboard Extension
//
// Keyboard extensions cannot call `UIApplication.shared`; walk the
// responder chain to reach the host app's `UIApplication` instead.

import UIKit

@MainActor
enum ExtensionScreenWakeLock {
    private static var holdCount = 0
    private static weak var capturedApplication: UIApplication?

    static func acquire(from responder: UIResponder) {
        holdCount += 1
        if holdCount == 1 {
            capturedApplication = findApplication(from: responder)
            capturedApplication?.isIdleTimerDisabled = true
        }
    }

    static func release() {
        guard holdCount > 0 else { return }
        holdCount -= 1
        if holdCount == 0 {
            capturedApplication?.isIdleTimerDisabled = false
            capturedApplication = nil
        }
    }

    static func releaseAll() {
        holdCount = 0
        capturedApplication?.isIdleTimerDisabled = false
        capturedApplication = nil
    }

    private static func findApplication(from responder: UIResponder) -> UIApplication? {
        var current: UIResponder? = responder
        while let node = current {
            if let application = node as? UIApplication { return application }
            current = node.next
        }
        return nil
    }
}
