// AppURLHandler.swift
// OSGKeyboard · Main App
//
// Captures `sourceApplication` from UIKit open-URL options (scheme D).

import UIKit
import OSGKeyboardShared

extension Notification.Name {
    static let osgKeyboardOpenURL = Notification.Name("osgkeyboard.openURL")
}

final class AppURLHandler: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if let source = options[.sourceApplication] as? String {
            FlowSessionBridge.setPendingHostBundleId(source)
        }
        NotificationCenter.default.post(
            name: .osgKeyboardOpenURL,
            object: nil,
            userInfo: ["url": url]
        )
        return true
    }
}
