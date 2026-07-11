// HostAppLauncher.swift
// OSGKeyboard · Keyboard Extension
//
// Opens the host app from the keyboard extension.
//
// Reality check (verified against iOS 18–26 behaviour):
//   • The deprecated `openURL:` selector hack was disabled in iOS 18
//     ("BUG IN CLIENT OF UIKIT … migrate to open(_:options:completionHandler:)").
//   • Primary path: walk the responder chain to `UIApplication` and call the
//     non-deprecated `open(_:options:completionHandler:)`. This requires Full
//     Access and grows less reliable on newer iOS, so we report the *real*
//     success from the completion handler instead of assuming it worked.
//   • Fallback: `extensionContext.open`. Historically documented for Today
//     widgets only (and it used to resolve `false` for keyboards), but it is
//     the Apple-documented API for extensions to open URLs and ships in
//     production keyboards on current iOS — worth trying before giving up.
//     When both paths fail, callers degrade to on-keyboard guidance.

import UIKit

enum HostAppLauncher {
    @MainActor
    static func open(
        url: URL,
        from controller: KeyboardViewController,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        var responder: UIResponder? = controller
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { success in
                    Task { @MainActor in
                        if success {
                            completion(true)
                        } else {
                            openViaExtensionContext(url: url, from: controller, completion: completion)
                        }
                    }
                }
                return
            }
            responder = current.next
        }
        // No `UIApplication` in the responder chain — try the extension context.
        openViaExtensionContext(url: url, from: controller, completion: completion)
    }

    @MainActor
    private static func openViaExtensionContext(
        url: URL,
        from controller: KeyboardViewController,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        guard let context = controller.extensionContext else {
            completion(false)
            return
        }
        // `NSExtensionContext.open` from keyboards has historically been
        // flaky about ever invoking its completion on some iOS versions.
        // Callers rely on a real answer to fail fast (instead of spinning
        // the 30 s start watchdog), so race the callback against a timeout
        // and report the first result only.
        var didComplete = false
        let finish: @MainActor (Bool) -> Void = { success in
            guard !didComplete else { return }
            didComplete = true
            completion(success)
        }
        Task { @MainActor in
            // 1.5 s: long enough for a real open to call back, short enough
            // that a dead completion degrades to on-keyboard guidance before
            // the user gives up staring at nothing.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            finish(false)
        }
        context.open(url) { success in
            Task { @MainActor in finish(success) }
        }
    }
}
