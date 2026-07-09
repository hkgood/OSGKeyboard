// ProviderConfig.swift
// OSGKeyboard · Shared
//
// User's LLM configuration. Persisted in App Group UserDefaults so both
// the main app and keyboard extension read the same values.
//
// `apiKey` is the exception: it lives in the Keychain (see
// `Keychain.swift`) for at-rest encryption. The first time this struct
// inits after upgrade, a legacy plaintext value from UserDefaults is
// migrated to the Keychain and removed from UserDefaults.

import Foundation
import Combine

public final class ProviderConfig: ObservableObject, @unchecked Sendable {
    public static let shared = ProviderConfig()

    @Published public var providerId: String {
        didSet {
            guard !isApplyingConfiguration, providerId != configuration.providerId else { return }
            configuration.providerId = providerId
            isSyncingProviderAPIKey = true
            apiKey = configuration.apiKey
            isSyncingProviderAPIKey = false
            persistConfiguration()
        }
    }
    @Published public var baseURL: String {
        didSet {
            guard !isApplyingConfiguration, baseURL != configuration.baseURL else { return }
            configuration.baseURL = baseURL
            persistConfiguration()
        }
    }
    @Published public var apiKey: String {
        didSet {
            guard oldValue != apiKey, !isSyncingProviderAPIKey else { return }
            do {
                try Keychain.setAPIKey(
                    apiKey,
                    for: providerId,
                    useICloudSync: configuration.settingsICloudSyncEnabled
                )
            } catch {
                OSGLog.config.warning("Keychain write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    @Published public var model: String {
        didSet {
            guard !isApplyingConfiguration, model != configuration.model else { return }
            configuration.model = model
            persistConfiguration()
        }
    }
    @Published public var modeId: String {
        didSet {
            guard !isApplyingConfiguration, modeId != configuration.modeId else { return }
            configuration.modeId = modeId
            persistConfiguration()
        }
    }
    @Published public var localeId: String {
        didSet {
            guard !isApplyingConfiguration, localeId != configuration.localeId else { return }
            configuration.localeId = localeId
            persistConfiguration()
        }
    }
    /// "local" → on-device ASR + built-in DeepSeek polish.
    /// "cloud" → provider cloud ASR (with personal dictionary) + user's cloud LLM polish.
    @Published public var engineMode: String {
        didSet {
            guard !isApplyingConfiguration, engineMode != configuration.engineMode else { return }
            configuration.engineMode = engineMode
            applyEngineModeSideEffects()
            persistConfiguration(postConfigChanged: true)
        }
    }
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  hasCompletedOnboarding != configuration.hasCompletedOnboarding else { return }
            configuration.hasCompletedOnboarding = hasCompletedOnboarding
            // Mirror to the reboot-durable Keychain marker so a device restart
            // can never resurrect the onboarding flow (or lose a replay reset).
            let newValue = hasCompletedOnboarding
            OSGLog.config.info("[onboarding] didSet → \(newValue, privacy: .public), mirroring to Keychain")
            Keychain.setOnboardingCompleted(hasCompletedOnboarding)
            if hasCompletedOnboarding {
                configuration.onboardingPage = 0
                onboardingPage = 0
            }
            persistConfiguration()
        }
    }
    /// Persisted onboarding step so returning from Settings does not reset progress.
    @Published public var onboardingPage: Int {
        didSet {
            guard !isApplyingConfiguration, onboardingPage != configuration.onboardingPage else { return }
            configuration.onboardingPage = onboardingPage
            persistConfiguration()
        }
    }
    /// User confirmed that Cloud polish sends transcripts to their configured third-party API.
    @Published public var hasAcknowledgedCloudSharing: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  hasAcknowledgedCloudSharing != configuration.hasAcknowledgedCloudSharing else { return }
            configuration.hasAcknowledgedCloudSharing = hasAcknowledgedCloudSharing
            persistConfiguration()
        }
    }
    /// Host-app UI language. Also mirrored to the App Group for the keyboard extension.
    @Published public var uiLanguage: AppUILanguage {
        didSet {
            guard !isApplyingConfiguration, uiLanguage != configuration.uiLanguage else { return }
            configuration.uiLanguage = uiLanguage
            persistConfiguration()
        }
    }
    /// v0.2.1: whether to translate the transcript into
    /// `translationTargetLocaleId` before insertion. **Derived** —
    /// translation is on iff the user has selected a target locale
    /// (i.e. the persisted id is anything other than
    /// `TranslationLanguageCatalog.offLocaleId`). Default off.
    public var translationEnabled: Bool {
        configuration.translationEnabled
    }
    /// v0.2.1: BCP-47-ish target language id (e.g. `en`, `ja`, `ko`) the
    /// translate-and-polish prompt should produce. Default `"off"` —
    /// translation is opt-in. Persisted in the App Group so the keyboard
    /// extension can honour it (and so the chip on the keyboard reflects
    /// the user's choice without a host-app round-trip).
    @Published public var translationTargetLocaleId: String {
        didSet {
            guard !isApplyingConfiguration,
                  translationTargetLocaleId != configuration.translationTargetLocaleId else { return }
            configuration.translationTargetLocaleId = translationTargetLocaleId
            persistConfiguration(postConfigChanged: true)
        }
    }
    /// Which hand the user holds the phone with — mirrors to the keyboard
    /// extension so delete / return can swap on the bottom row.
    @Published public var handednessPreference: HandednessPreference {
        didSet {
            guard !isApplyingConfiguration,
                  handednessPreference != configuration.handednessPreference else { return }
            configuration.handednessPreference = handednessPreference
            persistConfiguration(postConfigChanged: true)
        }
    }

    /// Press-and-drag pads beside the mic for four-way caret movement.
    @Published public var cursorDragNavigationEnabled: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  cursorDragNavigationEnabled != configuration.cursorDragNavigationEnabled else { return }
            configuration.cursorDragNavigationEnabled = cursorDragNavigationEnabled
            persistConfiguration(postConfigChanged: true)
        }
    }

    /// Whether the pipeline should run translate-and-polish (not just
    /// polish). Both engines honour the selected target locale.
    public var isTranslationEffective: Bool {
        configuration.isTranslationEffective
    }

    /// Translation picker visibility — available on both engines.
    public var isTranslationRowVisible: Bool { true }

    /// v0.3.0: how aggressively the LLM should rewrite the ASR
    /// transcript. Default is `medium` (Typeless-equivalent).
    @Published public var polishIntensity: PolishIntensity {
        didSet {
            guard !isApplyingConfiguration, polishIntensity != configuration.polishIntensity else { return }
            configuration.polishIntensity = polishIntensity
            persistConfiguration()
        }
    }

    /// When enabled, the host app tries to return to the source app after a cold-start handoff.
    @Published public var flowSkipAppSwitch: Bool {
        didSet {
            guard !isApplyingConfiguration, flowSkipAppSwitch != configuration.flowSkipAppSwitch else { return }
            configuration.flowSkipAppSwitch = flowSkipAppSwitch
            persistConfiguration()
        }
    }

    /// Idle window before an active Flow session expires; resets on each utterance.
    @Published public var flowInactivityDuration: FlowInactivityDuration {
        didSet {
            guard !isApplyingConfiguration,
                  flowInactivityDuration != configuration.flowInactivityDuration else { return }
            configuration.flowInactivityDuration = flowInactivityDuration
            persistConfiguration()
        }
    }

    /// Diagnostic switch: disable to isolate whether the custom language model
    /// is causing local SpeechAnalyzer to return empty results.
    @Published public var localASRCustomLanguageModelEnabled: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  localASRCustomLanguageModelEnabled != configuration.localASRCustomLanguageModelEnabled else {
                return
            }
            configuration.localASRCustomLanguageModelEnabled = localASRCustomLanguageModelEnabled
            persistConfiguration()
        }
    }

    public var isConfigured: Bool {
        // Local engine uses on-device ASR + built-in DeepSeek polish and
        // does not need a user API key. Cloud needs base URL, key, and model.
        if isLocalEngine { return true }
        return !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    /// On-device ASR only; no cloud API required.
    public var isLocalEngine: Bool { configuration.isLocalEngine }

    /// Local engine always polishes via the built-in DeepSeek path.
    public var shouldPolishLocalTranscript: Bool { isLocalEngine }

    /// Cloud engine uses `providerId`. Local engine pins DeepSeek.
    public var localModeProviderId: String { "deepseek" }

    private let defaults: UserDefaults
    private var configuration: AppGroupConfiguration
    private var isApplyingConfiguration = false
    private var isSyncingProviderAPIKey = false

    public init(defaults: UserDefaults? = nil) {
        guard let resolvedDefaults = defaults ?? AppGroup.defaultsIfAvailable else {
            preconditionFailure(
                "ProviderConfig requires App Group or injected UserDefaults — " +
                "check AppGroup.isAvailable before constructing."
            )
        }
        self.defaults = resolvedDefaults
        self.configuration = AppGroupConfiguration.load(fromAvailable: resolvedDefaults)

        // Onboarding completion must survive a device reboot. App Group
        // UserDefaults can transiently read empty right after boot, which would
        // falsely re-show onboarding. Trust the durable Keychain marker when the
        // App Group value looks unset, and backfill it once the App Group value
        // is confirmed true (covers users onboarded before this safeguard).
        let appGroupOnboarding = configuration.hasCompletedOnboarding
        let keychainOnboarding = Keychain.hasCompletedOnboarding()
        // Distinguish "key absent" (nil → plist not loaded / data-protection race)
        // from "key present == false" (something actually wrote false).
        let rawKeyPresent = resolvedDefaults.object(forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding) != nil
        OSGLog.config.info(
            "[onboarding] init: appGroup=\(appGroupOnboarding, privacy: .public) (keyPresent=\(rawKeyPresent, privacy: .public)), keychain=\(keychainOnboarding, privacy: .public)"
        )
        if appGroupOnboarding {
            Keychain.setOnboardingCompleted(true)
        } else if keychainOnboarding {
            configuration.hasCompletedOnboarding = true
            OSGLog.config.info("[onboarding] init: App Group read false but Keychain true → restored to true")
        }
        let finalOnboarding = configuration.hasCompletedOnboarding
        OSGLog.config.info("[onboarding] init: final=\(finalOnboarding, privacy: .public)")

        isApplyingConfiguration = true
        providerId = configuration.providerId
        baseURL = configuration.baseURL
        apiKey = configuration.apiKey
        model = configuration.model
        modeId = configuration.modeId
        localeId = configuration.localeId
        engineMode = configuration.engineMode
        hasCompletedOnboarding = configuration.hasCompletedOnboarding
        onboardingPage = configuration.onboardingPage
        hasAcknowledgedCloudSharing = configuration.hasAcknowledgedCloudSharing
        uiLanguage = configuration.uiLanguage
        translationTargetLocaleId = configuration.translationTargetLocaleId
        handednessPreference = configuration.handednessPreference
        cursorDragNavigationEnabled = configuration.cursorDragNavigationEnabled
        polishIntensity = configuration.polishIntensity
        flowSkipAppSwitch = configuration.flowSkipAppSwitch
        flowInactivityDuration = configuration.flowInactivityDuration
        localASRCustomLanguageModelEnabled = configuration.localASRCustomLanguageModelEnabled
        isApplyingConfiguration = false
    }

    /// Keep cloud vs local provider choices isolated when the user
    /// switches engines in Settings / onboarding.
    private func applyEngineModeSideEffects() {
        if engineMode == "cloud", providerId == "deepseek" {
            apply(preset: LLMProvider.provider(id: "openai"))
        }
    }

    private func persistConfiguration(postConfigChanged: Bool = false) {
        configuration.save(to: defaults)
        if postConfigChanged {
            AppGroupConfigDarwin.postConfigChanged()
        }
        scheduleSettingsCloudPushIfEnabled()
    }

    /// Re-read App Group defaults after a cloud pull updates the cache.
    public func reloadFromPersistedStorage() {
        var fresh = AppGroupConfiguration.load(fromAvailable: defaults)
        // Keep the reboot-durable onboarding marker authoritative across cloud
        // pulls, matching the resilience applied at init.
        let freshOnboarding = fresh.hasCompletedOnboarding
        let keychainOnboarding = Keychain.hasCompletedOnboarding()
        OSGLog.config.info(
            "[onboarding] reload: appGroup=\(freshOnboarding, privacy: .public), keychain=\(keychainOnboarding, privacy: .public)"
        )
        if freshOnboarding {
            Keychain.setOnboardingCompleted(true)
        } else if keychainOnboarding {
            fresh.hasCompletedOnboarding = true
            OSGLog.config.info("[onboarding] reload: App Group read false but Keychain true → restored to true")
        }
        isApplyingConfiguration = true
        configuration = fresh
        providerId = fresh.providerId
        baseURL = fresh.baseURL
        model = fresh.model
        modeId = fresh.modeId
        localeId = fresh.localeId
        engineMode = fresh.engineMode
        hasCompletedOnboarding = fresh.hasCompletedOnboarding
        onboardingPage = fresh.onboardingPage
        hasAcknowledgedCloudSharing = fresh.hasAcknowledgedCloudSharing
        uiLanguage = fresh.uiLanguage
        translationTargetLocaleId = fresh.translationTargetLocaleId
        handednessPreference = fresh.handednessPreference
        cursorDragNavigationEnabled = fresh.cursorDragNavigationEnabled
        polishIntensity = fresh.polishIntensity
        flowSkipAppSwitch = fresh.flowSkipAppSwitch
        flowInactivityDuration = fresh.flowInactivityDuration
        localASRCustomLanguageModelEnabled = fresh.localASRCustomLanguageModelEnabled
        isSyncingProviderAPIKey = true
        apiKey = fresh.apiKey
        isSyncingProviderAPIKey = false
        isApplyingConfiguration = false
    }

    private func scheduleSettingsCloudPushIfEnabled() {
        guard configuration.settingsICloudSyncEnabled else { return }
        Task { @MainActor in
            try? await SettingsCloudSync.shared.pushLocalIfEnabled()
        }
    }

    public func apply(preset: LLMProvider) {
        isApplyingConfiguration = true
        providerId = preset.id
        if !preset.defaultBaseURL.isEmpty {
            baseURL = preset.defaultBaseURL
        }
        if !preset.defaultModel.isEmpty {
            model = preset.defaultModel
        }
        configuration.providerId = providerId
        configuration.baseURL = baseURL
        configuration.model = model
        isSyncingProviderAPIKey = true
        apiKey = configuration.apiKey
        isSyncingProviderAPIKey = false
        isApplyingConfiguration = false
        persistConfiguration()
    }

    public func reset() {
        isApplyingConfiguration = true
        let preset = LLMProvider.provider(id: "openai")
        providerId = preset.id
        baseURL = preset.defaultBaseURL
        apiKey = ""
        model = preset.defaultModel
        handednessPreference = .left
        localASRCustomLanguageModelEnabled = true
        hasAcknowledgedCloudSharing = false
        configuration.providerId = preset.id
        configuration.baseURL = preset.defaultBaseURL
        configuration.model = preset.defaultModel
        configuration.handednessPreference = .left
        configuration.localASRCustomLanguageModelEnabled = true
        configuration.hasAcknowledgedCloudSharing = false
        isApplyingConfiguration = false
        persistConfiguration()
    }
}
