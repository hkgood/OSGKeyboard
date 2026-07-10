// ConfigurationStore.swift
// OSGKeyboard · Shared
//
// Cross-platform read facade for the dictation pipeline (ASR → polish).
// iOS implements this via `AppGroupStore` (App Group UserDefaults + Keychain).
// macOS will gain a separate implementation (standard UserDefaults + Keychain)
// without pulling in keyboard-extension-only APIs.

import Foundation

/// Read-only configuration surface consumed by ASR, cloud ASR, and polish services.
///
/// Keep this protocol narrow: only what the shared pipeline needs today.
/// Platform-specific settings UI and iCloud sync stay on concrete stores.
public protocol ConfigurationStore: Sendable {
    /// Polish / LLM provider id.
    var providerId: String { get }
    var baseURL: String { get }
    var apiKey: String { get }
    var model: String { get }

    /// Cloud ASR provider id — independent from polish when `engineMode == "cloud"`.
    var asrProviderId: String { get }
    var asrBaseURL: String { get }
    var asrApiKey: String { get }
    var asrModel: String { get }

    var engineMode: String { get }
    var polishIntensity: PolishIntensity { get }
    var personalDictionary: PersonalDictionary { get }

    /// Foreground-app context for polish prompts (keyboard extension publishes this).
    var detectedAppContext: (context: AppContext, observedAt: Date)? { get }

    /// Provider-specific ASR caches (e.g. Alibaba Fun-ASR vocabulary IDs).
    var cloudASRPersistence: UserDefaults { get }

    func makeClient() -> LLMClient
}
