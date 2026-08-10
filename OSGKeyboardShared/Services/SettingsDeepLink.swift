// SettingsDeepLink.swift
// OSGKeyboard · Shared
//
// One-shot deep-link target for the host Settings stack (keyboard → app).

import Foundation

public enum SettingsDeepLink: String, Sendable {
    case clipboard

    private static let pendingKey = "settings.pendingDeepLink"

    public static func setPending(_ link: SettingsDeepLink?) {
        guard let defaults = AppGroup.defaultsIfAvailable else { return }
        if let link {
            defaults.set(link.rawValue, forKey: pendingKey)
        } else {
            defaults.removeObject(forKey: pendingKey)
        }
        defaults.synchronize()
    }

    public static func consumePending() -> SettingsDeepLink? {
        guard let defaults = AppGroup.defaultsIfAvailable else { return nil }
        guard let raw = defaults.string(forKey: pendingKey) else { return nil }
        defaults.removeObject(forKey: pendingKey)
        defaults.synchronize()
        return SettingsDeepLink(rawValue: raw)
    }
}

public extension Notification.Name {
    static let osgOpenSettingsDeepLink = Notification.Name("osg.OpenSettingsDeepLink")
}
