// AppGroupConfigDarwin.swift
// OSGKeyboard · Shared
//
// Cross-process Darwin notification when App Group config changes
// (translation target, cloud-polish toggle, etc.). Lets the host app
// and keyboard extension pick up writes without waiting on the 1 Hz poll.

import Foundation

public enum AppGroupConfigDarwin {
    public static let notificationName = "com.osgkeyboard.config.changed"

    public static func postConfigChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}

/// Cross-process Darwin notification for clipboard-history writes.
///
/// History is one whole-array JSON blob under a single key, so a peer holding a
/// stale in-memory copy silently reverts the other side's deletes (and drops
/// its new entries) on its next write. Every other shared surface already has a
/// notification; this one did not.
///
/// A suspended process never receives Darwin notifications, so this covers only
/// the window where both processes are alive. The host must still reload when it
/// returns to the foreground.
public enum ClipboardHistoryDarwin {
    public static let notificationName = "com.osgkeyboard.clipboard.history.changed"

    public static func postHistoryChanged() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil,
            nil,
            true
        )
    }
}
