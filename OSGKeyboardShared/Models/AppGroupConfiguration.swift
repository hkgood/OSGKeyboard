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
        /// Credential ownership is independent from local/cloud ASR selection.
        public static let credentialSource = "config.credentialSource"
        public static let hasCompletedOnboarding = "config.hasCompletedOnboarding"
        public static let onboardingPage = "config.onboardingPage"
        public static let hasAcknowledgedCloudSharing = "config.hasAcknowledgedCloudSharing"
        public static let uiLanguage = "config.uiLanguage"
        public static let translationTargetLocaleId = "config.translationTargetLocaleId"
        public static let handednessPreference = "config.handednessPreference"
        public static let cursorDragNavigationEnabled = "config.cursorDragNavigationEnabled"
        public static let keyboardHapticIntensity = "config.keyboardHapticIntensity"
        public static let polishIntensity = "config.polishIntensity"
        public static let aiResponseLength = "config.aiResponseLength"
        public static let llmThinkingEnabled = "config.llmThinkingEnabled"
        /// When true, the keyboard records system clipboard text into local history.
        public static let clipboardHistoryEnabled = "config.clipboardHistoryEnabled"
        /// When true (and history is on), show the newest clipboard item as a suggestion strip.
        public static let clipboardCandidateBarEnabled = "config.clipboardCandidateBarEnabled"
        public static let detectedAppContext = "config.detectedAppContext"
        public static let detectedAppContextAt = "config.detectedAppContextAt"
        public static let personalDictionary = "config.personalDictionary.v1"
        public static let polishStyleCatalog = "config.polishStyles.v1"
        public static let activePolishStyleId = "config.activePolishStyleId"
        public static let polishStylesMigrated = "config.polishStyles.migrated"
        /// Legacy keys from the removed manual scenario implementation.
        public static let legacyPolishScenarioId = "config.polishScenarioId"
        public static let legacySystemPrompt = "config.systemPrompt"
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
        /// One-shot: remap previous product defaults (30m / 10m) → 5m.
        public static let flowInactivityMigratedToFiveMinuteDefault =
            "config.flowInactivityDuration.migratedToFiveMinuteDefault"
        /// Diagnostic switch: when false, local ASR skips the custom language model.
        public static let localASRCustomLanguageModelEnabled = "config.localASR.customLanguageModelEnabled"
        /// Enabled AI Agent skill IDs (order) + confirmed companion Shortcuts.
        public static let agentSkillLayout = "config.aiAgentSkills.layout.v1"
        /// User-created clipboard skills (no cloud sync; App Group only).
        public static let agentUserSkillCatalog = "config.aiAgentSkills.userCatalog.v1"
        /// Device-local ordered microphone preferences. UIDs are hardware-specific,
        /// so this intentionally stays outside the iCloud settings payload.
        public static let microphonePriority = "config.microphonePriority.v1"
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
    public var credentialSource: CredentialSource
    public var hasCompletedOnboarding: Bool
    public var onboardingPage: Int
    public var hasAcknowledgedCloudSharing: Bool
    public var uiLanguage: AppUILanguage
    public var translationTargetLocaleId: String
    public var handednessPreference: HandednessPreference
    public var cursorDragNavigationEnabled: Bool
    /// Typing-grid haptic strength (off / light / strong).
    public var keyboardHapticIntensity: KeyboardHapticIntensity
    /// Safety envelope for built-in fun polish styles (light by default).
    public var polishIntensity: PolishIntensity
    /// Soft AI-mode answer length preference (medium by default).
    public var aiResponseLength: AIResponseLength
    /// Enables provider-specific reasoning / thinking controls for polish LLM requests.
    public var llmThinkingEnabled: Bool
    /// Opt-in clipboard history capture in the keyboard extension.
    public var clipboardHistoryEnabled: Bool
    /// Opt-in clipboard suggestion strip above the key surfaces.
    public var clipboardCandidateBarEnabled: Bool
    public var personalDictionary: PersonalDictionary
    public var polishStyleCatalog: PolishStyleCatalog
    public var activePolishStyleId: String
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
        guard credentialSource == .byok else { return false }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var isCloudASRKeyMissing: Bool {
        guard engineMode == "cloud" else { return false }
        guard credentialSource == .byok else { return false }
        let key = asrApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return true }
        // Volcengine may store auth_mode JSON before credentials are filled.
        if asrProviderId == "volcengine" {
            return !VolcengineASRFields.parse(apiKey: key).hasUsableCredentials
        }
        return false
    }

    public var isPolishKeyMissing: Bool {
        guard credentialSource == .byok else { return false }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    public func makeClient(
        taskKind: ManagedGatewayTaskKind? = nil,
        requestPurpose: ManagedGatewayRequestPurpose? = nil
    ) -> LLMClient {
        if credentialSource == .managed {
            return ManagedLLMClient(
                capability: .polish,
                taskKind: taskKind,
                requestPurpose: requestPurpose,
                grants: GatewayGrantCoordinator()
            )
        }
        return OpenAICompatibleClient(
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

    /// Loads and idempotently migrates a known-available suite; this is not a
    /// pure read. Missing defaults distinguish upgrades (legacy cloud engine)
    /// from fresh installs (local engine) before being persisted.
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
            credentialSource: CredentialSource.fromStored(
                defaults.string(forKey: Keys.credentialSource)
            ),
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
            keyboardHapticIntensity: KeyboardHapticIntensity.fromStored(
                defaults.string(forKey: Keys.keyboardHapticIntensity)
            ),
            polishIntensity: PolishIntensity.resolve(
                storedRawValue: defaults.string(forKey: Keys.polishIntensity)
            ),
            aiResponseLength: AIResponseLength.resolve(
                storedRawValue: defaults.string(forKey: Keys.aiResponseLength)
            ),
            llmThinkingEnabled: defaults.bool(forKey: Keys.llmThinkingEnabled),
            clipboardHistoryEnabled: defaults.bool(forKey: Keys.clipboardHistoryEnabled),
            clipboardCandidateBarEnabled: defaults.bool(forKey: Keys.clipboardCandidateBarEnabled),
            personalDictionary: decodePersonalDictionary(from: defaults),
            polishStyleCatalog: decodePolishStyleCatalog(from: defaults),
            activePolishStyleId: defaults.string(forKey: Keys.activePolishStyleId)
                ?? PolishStylePackCatalog.defaultID,
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
            do {
                try Keychain.copyQwenASRKeyToBailian(
                    useICloudSync: config.settingsICloudSyncEnabled
                )
            } catch {
                OSGLog.config.warning(
                    "qwen ASR credential migration deferred: \(String(describing: error), privacy: .public)"
                )
            }
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

        // One-shot defaults for installs that predate explicit settings.
        // Preserve the legacy engine choice, but use the current privacy-safe
        // inactivity duration when the user has never selected one.
        let isExistingInstall = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        if defaults.string(forKey: Keys.engineMode) == nil {
            let resolved = isExistingInstall ? "cloud" : "local"
            config.engineMode = resolved
            defaults.set(resolved, forKey: Keys.engineMode)
        }
        if defaults.string(forKey: Keys.flowInactivityDuration) == nil {
            let resolved = FlowInactivityDuration.default
            config.flowInactivityDuration = resolved
            defaults.set(resolved.rawValue, forKey: Keys.flowInactivityDuration)
            defaults.set(true, forKey: Keys.flowInactivityMigratedToFiveMinuteDefault)
        } else if !defaults.bool(forKey: Keys.flowInactivityMigratedToFiveMinuteDefault) {
            // Previous product defaults were 30m then briefly 10m. Remap those
            // once so existing installs pick up the new 5-minute default; users
            // who later choose 30m / 10m again keep that choice.
            let previousDefaults: Set<String> = [
                FlowInactivityDuration.thirtyMinutes.rawValue,
                FlowInactivityDuration.tenMinutes.rawValue
            ]
            if previousDefaults.contains(config.flowInactivityDuration.rawValue) {
                config.flowInactivityDuration = .default
                defaults.set(FlowInactivityDuration.default.rawValue, forKey: Keys.flowInactivityDuration)
            }
            defaults.set(true, forKey: Keys.flowInactivityMigratedToFiveMinuteDefault)
        }

        // Cloud no longer exposes off/transcribe; migrate legacy values.
        if config.engineMode == "cloud", config.modeId != "polish" {
            config.modeId = "polish"
            defaults.set("polish", forKey: Keys.modeId)
        }
        migrateLegacyPolishStyleIfNeeded(configuration: &config, defaults: defaults)
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
        defaults.set(credentialSource.rawValue, forKey: Keys.credentialSource)
        defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        defaults.set(onboardingPage, forKey: Keys.onboardingPage)
        defaults.set(hasAcknowledgedCloudSharing, forKey: Keys.hasAcknowledgedCloudSharing)
        defaults.set(uiLanguage.rawValue, forKey: Keys.uiLanguage)
        defaults.set(translationTargetLocaleId, forKey: Keys.translationTargetLocaleId)
        defaults.set(handednessPreference.rawValue, forKey: Keys.handednessPreference)
        defaults.set(cursorDragNavigationEnabled, forKey: Keys.cursorDragNavigationEnabled)
        defaults.set(keyboardHapticIntensity.rawValue, forKey: Keys.keyboardHapticIntensity)
        defaults.set(polishIntensity.rawValue, forKey: Keys.polishIntensity)
        defaults.set(aiResponseLength.rawValue, forKey: Keys.aiResponseLength)
        defaults.set(llmThinkingEnabled, forKey: Keys.llmThinkingEnabled)
        defaults.set(clipboardHistoryEnabled, forKey: Keys.clipboardHistoryEnabled)
        defaults.set(clipboardCandidateBarEnabled, forKey: Keys.clipboardCandidateBarEnabled)
        defaults.set(activePolishStyleId, forKey: Keys.activePolishStyleId)
        defaults.set(flowSkipAppSwitch, forKey: Keys.flowSkipAppSwitch)
        defaults.set(flowInactivityDuration.rawValue, forKey: Keys.flowInactivityDuration)
        defaults.set(localASRCustomLanguageModelEnabled, forKey: Keys.localASRCustomLanguageModelEnabled)
        defaults.set(personalDictionaryICloudSyncEnabled, forKey: Keys.personalDictionaryICloudSyncEnabled)
        defaults.set(settingsICloudSyncEnabled, forKey: Keys.settingsICloudSyncEnabled)
        Self.encodePersonalDictionary(personalDictionary, to: defaults)
        Self.encodePolishStyleCatalog(polishStyleCatalog, to: defaults)
    }

    /// Persists only fields changed from the caller's last observed snapshot.
    ///
    /// Main app and keyboard extension are separate processes. Rewriting every
    /// key from a stale snapshot can undo a newer, unrelated setting written by
    /// the other process. Field-level writes keep unrelated updates intact.
    public func saveChanges(since baseline: Self, to defaults: UserDefaults) {
        func set<Value: Equatable>(_ value: Value, previous: Value, key: String) {
            guard value != previous else { return }
            defaults.set(value, forKey: key)
        }

        set(providerId, previous: baseline.providerId, key: Keys.providerId)
        set(baseURL, previous: baseline.baseURL, key: Keys.baseURL)
        set(model, previous: baseline.model, key: Keys.model)
        set(asrProviderId, previous: baseline.asrProviderId, key: Keys.asrProviderId)
        set(asrBaseURL, previous: baseline.asrBaseURL, key: Keys.asrBaseURL)
        set(asrModel, previous: baseline.asrModel, key: Keys.asrModel)
        set(modeId, previous: baseline.modeId, key: Keys.modeId)
        set(localeId, previous: baseline.localeId, key: Keys.localeId)
        set(engineMode, previous: baseline.engineMode, key: Keys.engineMode)
        set(
            credentialSource.rawValue,
            previous: baseline.credentialSource.rawValue,
            key: Keys.credentialSource
        )
        set(
            hasCompletedOnboarding,
            previous: baseline.hasCompletedOnboarding,
            key: Keys.hasCompletedOnboarding
        )
        set(onboardingPage, previous: baseline.onboardingPage, key: Keys.onboardingPage)
        set(
            hasAcknowledgedCloudSharing,
            previous: baseline.hasAcknowledgedCloudSharing,
            key: Keys.hasAcknowledgedCloudSharing
        )
        set(uiLanguage.rawValue, previous: baseline.uiLanguage.rawValue, key: Keys.uiLanguage)
        set(
            translationTargetLocaleId,
            previous: baseline.translationTargetLocaleId,
            key: Keys.translationTargetLocaleId
        )
        set(
            handednessPreference.rawValue,
            previous: baseline.handednessPreference.rawValue,
            key: Keys.handednessPreference
        )
        set(
            cursorDragNavigationEnabled,
            previous: baseline.cursorDragNavigationEnabled,
            key: Keys.cursorDragNavigationEnabled
        )
        set(
            keyboardHapticIntensity.rawValue,
            previous: baseline.keyboardHapticIntensity.rawValue,
            key: Keys.keyboardHapticIntensity
        )
        set(
            polishIntensity.rawValue,
            previous: baseline.polishIntensity.rawValue,
            key: Keys.polishIntensity
        )
        set(
            aiResponseLength.rawValue,
            previous: baseline.aiResponseLength.rawValue,
            key: Keys.aiResponseLength
        )
        set(
            llmThinkingEnabled,
            previous: baseline.llmThinkingEnabled,
            key: Keys.llmThinkingEnabled
        )
        set(
            clipboardHistoryEnabled,
            previous: baseline.clipboardHistoryEnabled,
            key: Keys.clipboardHistoryEnabled
        )
        set(
            clipboardCandidateBarEnabled,
            previous: baseline.clipboardCandidateBarEnabled,
            key: Keys.clipboardCandidateBarEnabled
        )
        set(
            activePolishStyleId,
            previous: baseline.activePolishStyleId,
            key: Keys.activePolishStyleId
        )
        set(flowSkipAppSwitch, previous: baseline.flowSkipAppSwitch, key: Keys.flowSkipAppSwitch)
        set(
            flowInactivityDuration.rawValue,
            previous: baseline.flowInactivityDuration.rawValue,
            key: Keys.flowInactivityDuration
        )
        set(
            localASRCustomLanguageModelEnabled,
            previous: baseline.localASRCustomLanguageModelEnabled,
            key: Keys.localASRCustomLanguageModelEnabled
        )
        set(
            personalDictionaryICloudSyncEnabled,
            previous: baseline.personalDictionaryICloudSyncEnabled,
            key: Keys.personalDictionaryICloudSyncEnabled
        )
        set(
            settingsICloudSyncEnabled,
            previous: baseline.settingsICloudSyncEnabled,
            key: Keys.settingsICloudSyncEnabled
        )

        if personalDictionary != baseline.personalDictionary {
            Self.encodePersonalDictionary(personalDictionary, to: defaults)
        }
        if polishStyleCatalog != baseline.polishStyleCatalog {
            Self.encodePolishStyleCatalog(polishStyleCatalog, to: defaults)
        }
    }

    // MARK: - Private helpers

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

    private static func decodePolishStyleCatalog(from defaults: UserDefaults) -> PolishStyleCatalog {
        guard let data = defaults.data(forKey: Keys.polishStyleCatalog) else { return .empty }
        do {
            return try JSONDecoder().decode(PolishStyleCatalog.self, from: data)
        } catch {
            OSGLog.config.warning("polishStyleCatalog decode failed: \(error.localizedDescription, privacy: .public)")
            return .empty
        }
    }

    private static func encodePolishStyleCatalog(_ catalog: PolishStyleCatalog, to defaults: UserDefaults) {
        do {
            defaults.set(try JSONEncoder().encode(catalog), forKey: Keys.polishStyleCatalog)
        } catch {
            OSGLog.config.warning("polishStyleCatalog encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func migrateLegacyPolishStyleIfNeeded(
        configuration: inout AppGroupConfiguration,
        defaults: UserDefaults
    ) {
        guard !defaults.bool(forKey: Keys.polishStylesMigrated) else { return }
        defer { defaults.set(true, forKey: Keys.polishStylesMigrated) }

        if let legacyPrompt = defaults.string(forKey: Keys.legacySystemPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyPrompt.isEmpty {
            let boundedPrompt = String(legacyPrompt.prefix(PolishStyleLimits.maximumPromptCharacters))
            let custom = PolishStylePack(name: "自定义", prompt: boundedPrompt)
            if (try? configuration.polishStyleCatalog.upsert(custom)) != nil {
                configuration.activePolishStyleId = custom.id
                defaults.set(custom.id, forKey: Keys.activePolishStyleId)
                encodePolishStyleCatalog(configuration.polishStyleCatalog, to: defaults)
            }
            return
        }

        let legacyMappings = [
            "daily_chat": "builtin.chat",
            "work": "builtin.formal",
            "document": "builtin.structured",
            "todo": "builtin.structured",
            "social_lifestyle": "builtin.xhs"
        ]
        if let legacyID = defaults.string(forKey: Keys.legacyPolishScenarioId),
           let mappedID = legacyMappings[legacyID] {
            configuration.activePolishStyleId = mappedID
            defaults.set(mappedID, forKey: Keys.activePolishStyleId)
        }
    }

    /// Resolves the provider-scoped Keychain item, then the legacy `current`
    /// account, then plaintext defaults. Legacy sources are removed after the
    /// selected local or synchronizable target is read back exactly.
    static func resolveAPIKey(
        defaults: UserDefaults?,
        providerId: String,
        preferICloudSync: Bool = false
    ) -> String {
        if let stored = Keychain.apiKey(for: providerId, preferICloudSync: preferICloudSync), !stored.isEmpty {
            return stored
        }
        if let legacyKeychain = Keychain.legacyAPIKey(), !legacyKeychain.isEmpty {
            do {
                try Keychain.migrateLegacyAPIKey(
                    to: providerId,
                    useICloudSync: preferICloudSync
                )
            } catch {
                OSGLog.config.warning(
                    "legacy Keychain credential migration deferred: \(String(describing: error), privacy: .public)"
                )
            }
            return legacyKeychain
        }
        if let defaults,
           let legacy = defaults.string(forKey: Keys.apiKeyLegacy),
           !legacy.isEmpty {
            do {
                try Keychain.copyAPIKeyToSelectedStorage(
                    legacy,
                    providerId: providerId,
                    useICloudSync: preferICloudSync
                )
                defaults.removeObject(forKey: Keys.apiKeyLegacy)
            } catch {
                OSGLog.config.warning(
                    "legacy defaults credential migration deferred: \(String(describing: error), privacy: .public)"
                )
            }
            return legacy
        }
        return ""
    }

    /// Resolves the ASR-scoped account first, then falls back to the matching
    /// polish-provider account used before ASR credentials were split.
    static func resolveASRAPIKey(
        defaults: UserDefaults?,
        providerId: String,
        preferICloudSync: Bool = false
    ) -> String {
        if let stored = Keychain.asrApiKey(for: providerId, preferICloudSync: preferICloudSync), !stored.isEmpty {
            return stored
        }
        if providerId == "bailian" {
            try? Keychain.copyQwenASRKeyToBailian(useICloudSync: preferICloudSync)
            if let migrated = Keychain.asrApiKey(
                for: providerId,
                preferICloudSync: preferICloudSync
            ), !migrated.isEmpty {
                return migrated
            }
            // Keep a compatibility read while older signed installs may still
            // hold the DashScope credential under qwen accounts.
            if let legacyQwen = Keychain.asrApiKey(
                for: "qwen",
                preferICloudSync: preferICloudSync
            ), !legacyQwen.isEmpty {
                return legacyQwen
            }
        }
        // Pre-split installs: one shared key under `provider.<id>`.
        return resolveAPIKey(defaults: defaults, providerId: providerId, preferICloudSync: preferICloudSync)
    }
}
