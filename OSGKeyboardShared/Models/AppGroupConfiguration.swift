// AppGroupConfiguration.swift
// OSGKeyboard · Shared
//
// Single source of truth for App Group UserDefaults keys (`config.*`).
// Both `ProviderConfig` (main app) and `AppGroupStore` (keyboard ext)
// should read/write through this type so keys and defaults stay aligned.

import Foundation

public struct AppGroupConfiguration: Sendable, Equatable {
    /// Default polish LLM for fresh installs (local + cloud pickers).
    public static let defaultPolishProviderId = "deepseek"
    /// Default cloud ASR provider for fresh installs (independent from polish).
    public static let defaultCloudASRProviderId = "volcengine"

    // MARK: - Keys

    public enum Keys {
        public static let providerId = "config.providerId"
        public static let baseURL = "config.baseURL"
        /// Legacy plaintext slot — migrated to Keychain on first read.
        public static let apiKeyLegacy = "config.apiKey"
        public static let model = "config.model"
        /// Cloud ASR provider — independent from polish `providerId`.
        public static let asrProviderId = "config.asrProviderId"
        public static let asrBaseURL = "config.asrBaseURL"
        public static let asrModel = "config.asrModel"
        public static let modeId = "config.modeId"
        public static let localeId = "config.localeId"
        public static let engineMode = "config.engineMode"
        public static let hasCompletedOnboarding = "config.hasCompletedOnboarding"
        public static let onboardingPage = "config.onboardingPage"
        public static let hasAcknowledgedCloudSharing = "config.hasAcknowledgedCloudSharing"
        public static let uiLanguage = "config.uiLanguage"
        public static let translationTargetLocaleId = "config.translationTargetLocaleId"
        public static let handednessPreference = "config.handednessPreference"
        public static let cursorDragNavigationEnabled = "config.cursorDragNavigationEnabled"
        public static let polishIntensity = "config.polishIntensity"
        public static let llmThinkingEnabled = "config.llmThinkingEnabled"
        public static let detectedAppContext = "config.detectedAppContext"
        public static let detectedAppContextAt = "config.detectedAppContextAt"
        public static let personalDictionary = "config.personalDictionary.v1"
        /// When true, the main app mirrors the personal dictionary via iCloud KVS.
        public static let personalDictionaryICloudSyncEnabled = "config.personalDictionary.iCloudSyncEnabled"
        /// When true, the main app mirrors user settings via iCloud KVS.
        public static let settingsICloudSyncEnabled = "config.settings.iCloudSyncEnabled"
        /// Wall-clock stamp of the last settings blob applied from iCloud KVS.
        public static let settingsCloudUpdatedAt = "config.settings.cloudUpdatedAt"
        /// Cached per-field settings merge payload (`SyncedAppSettingsV2`).
        public static let settingsCloudPayloadV2 = "config.settings.cloudPayload.v2"
        /// When true, the host app auto-returns to the source app after a cold-start handoff.
        public static let flowSkipAppSwitch = "config.flowSkipAppSwitch"
        /// Raw `FlowInactivityDuration` value; session expires after this idle window.
        public static let flowInactivityDuration = "config.flowInactivityDuration"
        /// Diagnostic switch: when false, local ASR skips the custom language model.
        public static let localASRCustomLanguageModelEnabled = "config.localASR.customLanguageModelEnabled"
    }

    // MARK: - Stored fields

    public var providerId: String
    public var baseURL: String
    public var model: String
    /// Cloud-engine speech-to-text provider (OpenLess-style split from polish).
    public var asrProviderId: String
    public var asrBaseURL: String
    public var asrModel: String
    public var modeId: String
    public var localeId: String
    public var engineMode: String
    public var hasCompletedOnboarding: Bool
    public var onboardingPage: Int
    public var hasAcknowledgedCloudSharing: Bool
    public var uiLanguage: AppUILanguage
    public var translationTargetLocaleId: String
    public var handednessPreference: HandednessPreference
    public var cursorDragNavigationEnabled: Bool
    public var polishIntensity: PolishIntensity
    /// Enables provider-specific reasoning / thinking controls for polish LLM requests.
    public var llmThinkingEnabled: Bool
    public var personalDictionary: PersonalDictionary
    /// Opt-in iCloud KVS sync for the personal dictionary (main app only).
    public var personalDictionaryICloudSyncEnabled: Bool
    /// Opt-in iCloud KVS sync for user settings (main app only).
    public var settingsICloudSyncEnabled: Bool
    /// Auto-return to the host app after `startflow` cold start (default on).
    public var flowSkipAppSwitch: Bool
    /// Idle timeout before the Flow session ends; resets on each utterance.
    public var flowInactivityDuration: FlowInactivityDuration
    /// Whether local `SpeechAnalyzer` should attach the prepared custom language model.
    public var localASRCustomLanguageModelEnabled: Bool

    // MARK: - Derived

    /// Translation is on iff a target locale other than `offLocaleId` is selected.
    public var translationEnabled: Bool {
        translationTargetLocaleId != TranslationLanguageCatalog.offLocaleId
    }

    public var isTranslationEffective: Bool {
        translationEnabled
    }

    public var isLocalEngine: Bool {
        engineMode == "local"
    }

    public var polishModeForPipeline: PolishingService.PolishMode {
        isTranslationEffective
            ? .translate(targetLocaleId: translationTargetLocaleId)
            : .polish
    }

    /// Polish LLM provider. Local engine no longer pins DeepSeek — user picks in Settings.
    public var polishProviderIdOverride: String? { nil }

    public var isCloudLLMKeyMissing: Bool {
        guard engineMode == "cloud" else { return false }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isCloudASRKeyMissing: Bool {
        guard engineMode == "cloud" else { return false }
        return asrApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isPolishKeyMissing: Bool {
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        return !PreconfiguredKeys.isDeepseekConfigured
    }

    public var isCloudAPIKeyMissingForVoiceInput: Bool {
        guard engineMode == "cloud" else { return false }
        return isCloudASRKeyMissing || isCloudLLMKeyMissing
    }

    /// Polish LLM uses `providerId` + Keychain `provider.<id>`.
    public var apiKey: String {
        Self.resolveAPIKey(
            defaults: nil,
            providerId: providerId,
            preferICloudSync: settingsICloudSyncEnabled
        )
    }

    /// Cloud ASR uses `asrProviderId` + Keychain `asr.<id>` (falls back to legacy `provider.<id>`).
    public var asrApiKey: String {
        Self.resolveASRAPIKey(
            defaults: nil,
            providerId: asrProviderId,
            preferICloudSync: settingsICloudSyncEnabled
        )
    }

    public func makeClient() -> LLMClient {
        OpenAICompatibleClient(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            providerId: providerId,
            thinkingEnabled: llmThinkingEnabled
        )
    }

    /// Resolved cloud ASR model — user override or catalog default.
    public var resolvedASRModel: String {
        let trimmed = asrModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return CloudASRModelCatalog.defaultModel(for: asrProviderId)
    }

    /// Resolved cloud ASR base URL for prompt-style providers.
    public var resolvedASRBaseURL: String {
        let trimmed = asrBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return LLMProvider.provider(id: asrProviderId).defaultBaseURL
    }

    // MARK: - Detected app context

    public func detectedAppContext(from defaults: UserDefaults) -> (context: AppContext, observedAt: Date)? {
        guard let raw = defaults.string(forKey: Keys.detectedAppContext),
              let value = AppContext(rawValue: raw)
        else { return nil }
        let timestamp = defaults.object(forKey: Keys.detectedAppContextAt) as? Date ?? .distantPast
        return (value, timestamp)
    }

    public mutating func setDetectedAppContext(_ context: AppContext, at date: Date = Date(), to defaults: UserDefaults) {
        defaults.set(context.rawValue, forKey: Keys.detectedAppContext)
        defaults.set(date, forKey: Keys.detectedAppContextAt)
    }

    // MARK: - Load / save

    /// Loads configuration from App Group defaults. Returns `nil` when the suite is unavailable.
    public static func load(from defaults: UserDefaults? = nil) -> AppGroupConfiguration? {
        guard let store = defaults ?? AppGroup.defaultsIfAvailable else { return nil }
        return load(fromAvailable: store)
    }

    /// Loads configuration from a known-available UserDefaults suite.
    public static func load(fromAvailable defaults: UserDefaults) -> AppGroupConfiguration {
        let storedProviderId = defaults.string(forKey: Keys.providerId)
        var config = AppGroupConfiguration(
            providerId: storedProviderId ?? defaultPolishProviderId,
            baseURL: "",
            model: "",
            asrProviderId: defaults.string(forKey: Keys.asrProviderId) ?? "",
            asrBaseURL: "",
            asrModel: "",
            modeId: defaults.string(forKey: Keys.modeId) ?? "polish",
            localeId: defaults.string(forKey: Keys.localeId) ?? "auto",
            // Privacy-critical default: `local` keeps raw audio on-device
            // (SpeechAnalyzer). The `cloud` engine uploads recorded audio to
            // the user's configured ASR provider and must stay an explicit,
            // acknowledged opt-in (see `hasAcknowledgedCloudSharing`) — a
            // cloud default would contradict every privacy claim the app
            // makes in its docs, App Store listing, and permission prompts.
            engineMode: defaults.string(forKey: Keys.engineMode) ?? "local",
            hasCompletedOnboarding: defaults.bool(forKey: Keys.hasCompletedOnboarding),
            onboardingPage: {
                let saved = defaults.integer(forKey: Keys.onboardingPage)
                return saved > 0 ? saved : 0
            }(),
            hasAcknowledgedCloudSharing: defaults.bool(forKey: Keys.hasAcknowledgedCloudSharing),
            uiLanguage: AppUILanguage.fromStored(defaults.string(forKey: Keys.uiLanguage)),
            translationTargetLocaleId: defaults.string(forKey: Keys.translationTargetLocaleId)
                ?? TranslationLanguageCatalog.offLocaleId,
            handednessPreference: HandednessPreference.fromStored(
                defaults.string(forKey: Keys.handednessPreference)
            ),
            cursorDragNavigationEnabled: {
                if defaults.object(forKey: Keys.cursorDragNavigationEnabled) == nil {
                    return true
                }
                return defaults.bool(forKey: Keys.cursorDragNavigationEnabled)
            }(),
            polishIntensity: resolvePolishIntensity(from: defaults),
            llmThinkingEnabled: defaults.bool(forKey: Keys.llmThinkingEnabled),
            personalDictionary: decodePersonalDictionary(from: defaults),
            personalDictionaryICloudSyncEnabled: {
                if defaults.object(forKey: Keys.personalDictionaryICloudSyncEnabled) == nil {
                    return true
                }
                return defaults.bool(forKey: Keys.personalDictionaryICloudSyncEnabled)
            }(),
            settingsICloudSyncEnabled: {
                if defaults.object(forKey: Keys.settingsICloudSyncEnabled) == nil {
                    return true
                }
                return defaults.bool(forKey: Keys.settingsICloudSyncEnabled)
            }(),
            flowSkipAppSwitch: {
                if defaults.object(forKey: Keys.flowSkipAppSwitch) == nil {
                    return true
                }
                return defaults.bool(forKey: Keys.flowSkipAppSwitch)
            }(),
            flowInactivityDuration: FlowInactivityDuration.fromStored(
                defaults.string(forKey: Keys.flowInactivityDuration)
            ),
            localASRCustomLanguageModelEnabled: {
                if defaults.object(forKey: Keys.localASRCustomLanguageModelEnabled) == nil {
                    return true
                }
                return defaults.bool(forKey: Keys.localASRCustomLanguageModelEnabled)
            }()
        )

        let preset = LLMProvider.provider(id: config.providerId)
        if config.baseURL.isEmpty {
            config.baseURL = defaults.string(forKey: Keys.baseURL) ?? preset.defaultBaseURL
        }
        if config.model.isEmpty {
            config.model = defaults.string(forKey: Keys.model) ?? preset.defaultModel
        }

        if config.asrProviderId.isEmpty {
            // Pre-split installs only stored `providerId`; copy it so ASR keeps working.
            config.asrProviderId = storedProviderId ?? defaultCloudASRProviderId
            defaults.set(config.asrProviderId, forKey: Keys.asrProviderId)
        }
        let asrPreset = LLMProvider.provider(id: config.asrProviderId)
        if config.asrBaseURL.isEmpty {
            config.asrBaseURL = defaults.string(forKey: Keys.asrBaseURL) ?? asrPreset.defaultBaseURL
        }
        if config.asrModel.isEmpty {
            config.asrModel = defaults.string(forKey: Keys.asrModel)
                ?? CloudASRModelCatalog.defaultModel(for: config.asrProviderId)
        }

        // Legacy qwen cloud ASR → bailian realtime (HTTP Flash path removed).
        if config.asrProviderId == "qwen" {
            let bailian = LLMProvider.provider(id: "bailian")
            config.asrProviderId = "bailian"
            config.asrBaseURL = bailian.defaultBaseURL
            config.asrModel = CloudASRModelCatalog.alibabaFunASRRealtime
            defaults.set(config.asrProviderId, forKey: Keys.asrProviderId)
            defaults.set(config.asrBaseURL, forKey: Keys.asrBaseURL)
            defaults.set(config.asrModel, forKey: Keys.asrModel)
        }

        // One-shot legacy migration: plaintext apiKey in UserDefaults → Keychain.
        _ = resolveAPIKey(
            defaults: defaults,
            providerId: config.providerId,
            preferICloudSync: config.settingsICloudSyncEnabled
        )

        // One-shot default migration for installs that predate an explicit
        // stored value. The privacy-safe defaults ("local", 30 min TTL) are
        // for NEW installs only — an existing user who ran on the old
        // defaults must keep their behavior, both because silently changing
        // engines under someone is wrong, and because iCloud settings sync
        // would stamp the flip as a fresh "edit" and propagate it to every
        // other device, overriding choices made there. Persisting the
        // resolved value makes the decision stable and sync-invisible.
        let isExistingInstall = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        if defaults.string(forKey: Keys.engineMode) == nil {
            let resolved = isExistingInstall ? "cloud" : "local"
            config.engineMode = resolved
            defaults.set(resolved, forKey: Keys.engineMode)
        }
        if defaults.string(forKey: Keys.flowInactivityDuration) == nil {
            let resolved: FlowInactivityDuration = isExistingInstall ? .twelveHours : .default
            config.flowInactivityDuration = resolved
            defaults.set(resolved.rawValue, forKey: Keys.flowInactivityDuration)
        }

        // Cloud no longer exposes off/transcribe; migrate legacy values.
        if config.engineMode == "cloud", config.modeId != "polish" {
            config.modeId = "polish"
            defaults.set("polish", forKey: Keys.modeId)
        }
        return config
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(providerId, forKey: Keys.providerId)
        defaults.set(baseURL, forKey: Keys.baseURL)
        defaults.set(model, forKey: Keys.model)
        defaults.set(asrProviderId, forKey: Keys.asrProviderId)
        defaults.set(asrBaseURL, forKey: Keys.asrBaseURL)
        defaults.set(asrModel, forKey: Keys.asrModel)
        defaults.set(modeId, forKey: Keys.modeId)
        defaults.set(localeId, forKey: Keys.localeId)
        defaults.set(engineMode, forKey: Keys.engineMode)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        defaults.set(onboardingPage, forKey: Keys.onboardingPage)
        defaults.set(hasAcknowledgedCloudSharing, forKey: Keys.hasAcknowledgedCloudSharing)
        defaults.set(uiLanguage.rawValue, forKey: Keys.uiLanguage)
        defaults.set(translationTargetLocaleId, forKey: Keys.translationTargetLocaleId)
        defaults.set(handednessPreference.rawValue, forKey: Keys.handednessPreference)
        defaults.set(cursorDragNavigationEnabled, forKey: Keys.cursorDragNavigationEnabled)
        defaults.set(polishIntensity.rawValue, forKey: Keys.polishIntensity)
        defaults.set(llmThinkingEnabled, forKey: Keys.llmThinkingEnabled)
        defaults.set(flowSkipAppSwitch, forKey: Keys.flowSkipAppSwitch)
        defaults.set(flowInactivityDuration.rawValue, forKey: Keys.flowInactivityDuration)
        defaults.set(localASRCustomLanguageModelEnabled, forKey: Keys.localASRCustomLanguageModelEnabled)
        defaults.set(personalDictionaryICloudSyncEnabled, forKey: Keys.personalDictionaryICloudSyncEnabled)
        defaults.set(settingsICloudSyncEnabled, forKey: Keys.settingsICloudSyncEnabled)
        Self.encodePersonalDictionary(personalDictionary, to: defaults)
    }

    // MARK: - Private helpers

    private static func resolvePolishIntensity(from defaults: UserDefaults) -> PolishIntensity {
        guard let raw = defaults.string(forKey: Keys.polishIntensity) else {
            return .default
        }
        let resolved = PolishIntensity.resolve(storedRawValue: raw)
        if raw == PolishIntensity.legacyOffRawValue {
            defaults.set(resolved.rawValue, forKey: Keys.polishIntensity)
        }
        return resolved
    }

    private static func decodePersonalDictionary(from defaults: UserDefaults) -> PersonalDictionary {
        guard let data = defaults.data(forKey: Keys.personalDictionary) else {
            return .empty
        }
        do {
            var dictionary = try JSONDecoder().decode(PersonalDictionary.self, from: data)
            if dictionary.entries.contains(where: { $0.source == .history }) {
                for index in dictionary.entries.indices where dictionary.entries[index].source == .history {
                    dictionary.entries[index].source = .manual
                }
                dictionary.version += 1
                if let migrated = try? JSONEncoder().encode(dictionary) {
                    defaults.set(migrated, forKey: Keys.personalDictionary)
                }
            }
            return dictionary
        } catch {
            OSGLog.config.warning("personalDictionary decode failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    private static func encodePersonalDictionary(_ dictionary: PersonalDictionary, to defaults: UserDefaults) {
        do {
            let data = try JSONEncoder().encode(dictionary)
            defaults.set(data, forKey: Keys.personalDictionary)
        } catch {
            OSGLog.config.warning("personalDictionary encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Read the API key from the Keychain, falling back to a one-time migration from UserDefaults.
    static func resolveAPIKey(
        defaults: UserDefaults?,
        providerId: String,
        preferICloudSync: Bool = false
    ) -> String {
        if let stored = Keychain.apiKey(for: providerId, preferICloudSync: preferICloudSync), !stored.isEmpty {
            return stored
        }
        if let legacyKeychain = Keychain.legacyAPIKey(), !legacyKeychain.isEmpty {
            try? Keychain.setAPIKey(legacyKeychain, for: providerId, useICloudSync: preferICloudSync)
            try? Keychain.deleteLegacyAPIKey()
            return legacyKeychain
        }
        if let defaults,
           let legacy = defaults.string(forKey: Keys.apiKeyLegacy),
           !legacy.isEmpty {
            try? Keychain.setAPIKey(legacy, for: providerId, useICloudSync: preferICloudSync)
            defaults.removeObject(forKey: Keys.apiKeyLegacy)
            return legacy
        }
        return ""
    }

    static func resolveASRAPIKey(
        defaults: UserDefaults?,
        providerId: String,
        preferICloudSync: Bool = false
    ) -> String {
        if let stored = Keychain.asrApiKey(for: providerId, preferICloudSync: preferICloudSync), !stored.isEmpty {
            return stored
        }
        // Pre-split installs: one shared key under `provider.<id>`.
        return resolveAPIKey(defaults: defaults, providerId: providerId, preferICloudSync: preferICloudSync)
    }
}
