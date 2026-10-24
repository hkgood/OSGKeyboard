// HostReturnService.swift
// OSGKeyboard · Main App
//
// Opens a whitelisted host-app URL after a cold-start Flow handoff.
//
// No `canOpenURL` pre-check: iOS caps `LSApplicationQueriesSchemes` at 50
// entries (already spent) and the whitelist is far larger. `open` needs no
// declaration and reports failure through its completion instead.

import OSGKeyboardShared
import UIKit

enum HostReturnService {
    /// Attempts to return to the pending host app. Clears the pending bundle id on success.
    @MainActor
    static func openPendingHostIfPossible() -> Bool {
        let bundleId = FlowSessionBridge.pendingHostBundleId()
        guard let entry = HostAppURLRegistry.lookup(bundleId: bundleId),
              let url = entry.returnURL else {
            logReturn(bundleId: bundleId, outcome: "no-entry")
            return false
        }
        UIApplication.shared.open(url, options: [:]) { success in
            logReturn(bundleId: bundleId, outcome: success ? "opened" : "open-failed")
            if success {
                FlowSessionBridge.clearPendingHostBundleId()
            }
        }
        return true
    }

    @MainActor
    static func openHost(entry: HostAppEntry) -> Bool {
        guard let url = entry.returnURL else {
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

    private static func logReturn(bundleId: String?, outcome: String) {
        #if DEBUG
        HostBundleProbeLog.append(event: "return", bundleId: bundleId, detail: outcome)
        #endif
    }
}
