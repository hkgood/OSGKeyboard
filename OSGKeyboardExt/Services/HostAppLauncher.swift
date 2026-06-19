// HostAppLauncher.swift
// OSGKeyboard · Keyboard Extension
//
// Opens the host app via URL using every extension-safe strategy:
// 1. `extensionContext.open` (official)
// 2. Responder-chain `UIApplication.open` (TypeWhisper pattern)
// 3. `sharedApplication` KVC fallback (common in full-access keyboards)

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
                    completion(openViaFallback(url, from: controller))
                }
            }
            return
        }
        completion(openViaFallback(url, from: controller))
    }

    @MainActor
    private static func openViaFallback(
        _ url: URL,
        from controller: KeyboardViewController
    ) -> Bool {
        if openViaResponderChain(url, from: controller) {
            return true
        }
        return openViaSharedApplication(url)
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

    @MainActor
    private static func openViaSharedApplication(_ url: URL) -> Bool {
        guard
            let application = UIApplication.value(forKeyPath: "sharedApplication") as? UIApplication
        else {
            return false
        }
        application.open(url, options: [:]) { _ in }
        return true
    }
}
