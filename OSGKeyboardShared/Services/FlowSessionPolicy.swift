// FlowSessionPolicy.swift
// OSGKeyboard · Shared
//
// Reads Flow session behaviour preferences from the App Group.

import Foundation

public enum FlowSessionPolicy {
    public static func skipAppSwitch(defaults: UserDefaults? = nil) -> Bool {
        let store = resolvedDefaults(defaults)
        if store.object(forKey: AppGroupConfiguration.Keys.flowSkipAppSwitch) == nil {
            return true
        }
        return store.bool(forKey: AppGroupConfiguration.Keys.flowSkipAppSwitch)
    }

    public static func inactivityDuration(defaults: UserDefaults? = nil) -> FlowInactivityDuration {
        let store = resolvedDefaults(defaults)
        return FlowInactivityDuration.fromStored(
            store.string(forKey: AppGroupConfiguration.Keys.flowInactivityDuration)
        )
    }

    public static func sessionDuration(defaults: UserDefaults? = nil) -> TimeInterval {
        inactivityDuration(defaults: defaults).timeInterval
    }

    public static func keepAliveMode(defaults: UserDefaults? = nil) -> FlowKeepAliveMode {
        let store = resolvedDefaults(defaults)
        return FlowKeepAliveMode.fromStored(
            store.string(forKey: AppGroupConfiguration.Keys.flowKeepAliveMode)
        )
    }

    /// PiP sessions have no inactivity expiry; only the Live Activity path times out.
    public static func usesInactivityExpiry(defaults: UserDefaults? = nil) -> Bool {
        keepAliveMode(defaults: defaults) == .liveActivity
    }

    private static func resolvedDefaults(_ defaults: UserDefaults?) -> UserDefaults {
        if let defaults { return defaults }
        guard let available = AppGroup.defaultsIfAvailable else {
            #if DEBUG
            fatalError("App Group unavailable — inject UserDefaults in tests.")
            #else
            fatalError("App Group unavailable.")
            #endif
        }
        return available
    }
}
