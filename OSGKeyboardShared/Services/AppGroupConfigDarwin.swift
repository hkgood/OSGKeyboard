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
