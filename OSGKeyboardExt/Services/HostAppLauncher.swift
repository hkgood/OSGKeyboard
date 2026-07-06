// HostAppLauncher.swift
// OSGKeyboard · Keyboard Extension
//
// Opens the host app from the keyboard extension.
//
// Reality check (verified against iOS 18–26 behaviour):
//   • `extensionContext.open` is documented for Today widgets only; for a
//     keyboard extension it resolves `false`, so we do not use it.
//   • The deprecated `openURL:` selector hack was disabled in iOS 18
//     ("BUG IN CLIENT OF UIKIT … migrate to open(_:options:completionHandler:)").
//   • The still-working path is: walk the responder chain to `UIApplication`
//     and call the non-deprecated `open(_:options:completionHandler:)`. This
//     requires Full Access and grows less reliable on newer iOS, so we report
//     the *real* success from the completion handler instead of assuming it
//     worked — callers degrade to on-keyboard guidance when it returns false.

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
                    Task { @MainActor in completion(success) }
                }
                return
            }
            responder = current.next
        }
        // No `UIApplication` in the responder chain — cannot open the host app.
        completion(false)
    }
}
