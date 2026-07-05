// PreconfiguredKeys.swift
// OSGKeyboard · Shared
//
// Built-in API keys for engine-specific polish vendors. The local engine
// pins DeepSeek; the actual key lives in `PreconfiguredKeys.local.swift`
// (gitignored) so it never ships in the public repo.
//
// `./Scripts/generate-xcodeproj.sh` copies
// `PreconfiguredKeys.local.swift.example` → `PreconfiguredKeys.local.swift`
// on first run. Replace the placeholder in the local file before
// distributing a build that uses the local engine.

import Foundation

public enum PreconfiguredKeys {
    /// Placeholder string we ship in the repo. Any value other than
    /// this is treated as "configured".
    private static let placeholder = "TODO_FILL_LATER_DEEPSEEK_KEY"

    /// DeepSeek API key for the local engine's built-in polish step.
    public static var deepseek: String {
        PreconfiguredKeysLocal.deepseek
    }

    public static var isDeepseekConfigured: Bool {
        deepseek != placeholder && !deepseek.isEmpty
    }

    #if DEBUG
    /// Forces a lazy init at app launch in DEBUG builds so the assert
    /// below fires immediately when somebody forgets to swap the
    /// placeholder. The boolean is intentionally unused at runtime —
    /// it's a tripwire.
    public static let debugDeepseekTripwire: Bool = {
        assert(
            isDeepseekConfigured,
            "DeepSeek preconfigured key not filled — copy PreconfiguredKeys.local.swift.example to PreconfiguredKeys.local.swift and set your key"
        )
        return isDeepseekConfigured
    }()

    /// Touch the tripwire so the assert fires at launch rather than
    /// only the first time the local engine actually tries to polish.
    /// Called from app startup; safe to invoke multiple times.
    public static func assertProductionReadinessAtLaunch() {
        _ = debugDeepseekTripwire
    }
    #endif
}
