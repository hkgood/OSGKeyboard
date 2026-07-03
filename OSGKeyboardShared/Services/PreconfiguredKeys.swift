// PreconfiguredKeys.swift
// OSGKeyboard · Shared
//
// v0.2.1 follow-up: preconfigured API keys for built-in cloud providers
// the keyboard ships with out of the box. Today the only one is DeepSeek
// — the local engine's default polish vendor (see
// `ProviderConfig.localModeProviderId`). Future builds may pre-fill
// additional providers as we harden them.
//
// These constants live in source so a developer building from the repo
// can swap in their own key once and have every Debug / TestFlight build
// "just work" without round-tripping the Keychain settings UI.
//
// IMPORTANT: Replace the placeholder string with a real key before
// shipping a build. The DEBUG assert below catches the placeholder at
// launch so nobody accidentally publishes an "always 401" build.

import Foundation

public enum PreconfiguredKeys {
    /// Placeholder string we ship in the repo. Any value other than
    /// this is treated as "configured".
    private static let placeholder = "TODO_FILL_LATER_DEEPSEEK_KEY"

    /// Preconfigured DeepSeek API key. Replace `placeholder` with a
    /// real key in `Sources/.../PreconfiguredKeys.swift` before
    /// distributing a build.
    public static let deepseek: String = "REMOVED_LEAKED_DEEPSEEK_KEY"

    #if DEBUG
    /// Forces a lazy init at app launch in DEBUG builds so the assert
    /// below fires immediately when somebody forgets to swap the
    /// placeholder. The boolean is intentionally unused at runtime —
    /// it's a tripwire.
    public static let isDeepseekConfigured: Bool = {
        assert(
            deepseek != placeholder,
            "DeepSeek preconfigured key not filled — replace TODO_FILL_LATER_DEEPSEEK_KEY in PreconfiguredKeys.swift before building"
        )
        return deepseek != placeholder
    }()

    /// Touch the tripwire so the assert fires at launch rather than
    /// only the first time the local engine actually tries to polish.
    /// Called from app startup; safe to invoke multiple times.
    public static func assertProductionReadinessAtLaunch() {
        _ = isDeepseekConfigured
    }
    #endif
}
