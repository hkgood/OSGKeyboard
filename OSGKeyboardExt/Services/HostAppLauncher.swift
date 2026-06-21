// HostAppLauncher.swift
// OSGKeyboard · Keyboard Extension
//
// Opens the host app via URL using extension-safe strategies:
// 1. `extensionContext.open` (official)
// 2. Responder-chain `UIApplication.open` (TypeWhisper pattern)

import UIKit

enum HostAppLauncher {
    @MainActor
    static func open(
        url: URL,
        from controller: KeyboardViewController,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        if let context = controller.extensionContext {
            context.open(url) { success in
                Task { @MainActor in
                    if success {
                        completion(true)
                        return
                    }
                    completion(openViaResponderChain(url, from: controller))
                }
            }
            return
        }
        completion(openViaResponderChain(url, from: controller))
    }

    @MainActor
    private static func openViaResponderChain(
        _ url: URL,
        from controller: KeyboardViewController
    ) -> Bool {
        var responder: UIResponder? = controller
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { _ in }
                return true
            }
            responder = current.next
        }
        return false
    }
}
