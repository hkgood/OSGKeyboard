// HostReturnService.swift
// OSGKeyboard · Main App
//
// Opens a whitelisted host-app URL after a cold-start Flow handoff.

import UIKit
import OSGKeyboardShared

enum HostReturnService {
    /// Attempts to return to the pending host app. Clears the pending bundle id on success.
    @MainActor
    static func openPendingHostIfPossible() -> Bool {
        let bundleId = FlowSessionBridge.pendingHostBundleId()
        guard let entry = HostAppURLRegistry.lookup(bundleId: bundleId),
              let url = entry.returnURL else {
            return false
        }
        guard UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                FlowSessionBridge.clearPendingHostBundleId()
            }
        }
        return true
    }

    @MainActor
    static func openHost(entry: HostAppEntry) -> Bool {
        guard let url = entry.returnURL, UIApplication.shared.canOpenURL(url) else {
            return false
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if success {
                FlowSessionBridge.clearPendingHostBundleId()
            }
        }
        return true
    }

    @MainActor
    static func pendingHostEntry() -> HostAppEntry? {
        HostAppURLRegistry.lookup(bundleId: FlowSessionBridge.pendingHostBundleId())
    }
}
