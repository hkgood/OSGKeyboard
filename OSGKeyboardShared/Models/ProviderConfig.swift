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

/// UI-owned ObservableObject; construct and mutate it on the main thread.
/// `@unchecked Sendable` does not make `@Published` thread-safe. Credential
/// observers write only Keychain, while non-secret configuration uses App Group defaults.
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
    /// Its observer updates only the provider-scoped Keychain item; the value
    /// must never enter `configuration` or App Group UserDefaults.
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
                isSyncingProviderAPIKey = true
                apiKey = oldValue
                isSyncingProviderAPIKey = false
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
    @Published public var asrProviderId: String {
        didSet {
            guard !isApplyingConfiguration, asrProviderId != configuration.asrProviderId else { return }
            configuration.asrProviderId = asrProviderId
            isSyncingASRProviderAPIKey = true
            asrApiKey = configuration.asrApiKey
            isSyncingASRProviderAPIKey = false
            persistConfiguration()
        }
    }
    @Published public var asrBaseURL: String {
        didSet {
            guard !isApplyingConfiguration, asrBaseURL != configuration.asrBaseURL else { return }
            configuration.asrBaseURL = asrBaseURL
            persistConfiguration()
        }
    }
    @Published public var asrApiKey: String {
        didSet {
            guard oldValue != asrApiKey, !isSyncingASRProviderAPIKey else { return }
            do {
                try Keychain.setASRAPIKey(
                    asrApiKey,
                    for: asrProviderId,
                    useICloudSync: configuration.settingsICloudSyncEnabled
                )
            } catch {
                isSyncingASRProviderAPIKey = true
                asrApiKey = oldValue
                isSyncingASRProviderAPIKey = false
                OSGLog.config.warning("ASR Keychain write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    @Published public var asrModel: String {
        didSet {
            guard !isApplyingConfiguration, asrModel != configuration.asrModel else { return }
            configuration.asrModel = asrModel
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
    /// "local" → on-device ASR + user's LLM polish (requires user API key).
    /// "cloud" → user's cloud ASR + user's cloud LLM polish (independent picks).
    @Published public var engineMode: String {
        didSet {
            guard !isApplyingConfiguration, engineMode != configuration.engineMode else { return }
            configuration.engineMode = engineMode
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
                // Persist page reset immediately, but defer the @Published bump
                // so MainAppRoot's OnboardingView → MainTabView swap is not
                // coalesced with an in-flow page update (can freeze step 6).
                configuration.onboardingPage = 0
                let needsPublishedPageReset = onboardingPage != 0
                persistConfiguration()
                if needsPublishedPageReset {
                    Task { @MainActor in
                        guard self.hasCompletedOnboarding else { return }
                        self.onboardingPage = 0
                    }
                }
                return
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
    /// Whether to translate the transcript into
    /// `translationTargetLocaleId` before insertion. **Derived** —
    /// translation is on iff the user has selected a target locale
    /// (i.e. the persisted id is anything other than
    /// `TranslationLanguageCatalog.offLocaleId`). Default off.
    public var translationEnabled: Bool {
        configuration.translationEnabled
    }
    /// BCP-47-ish target language id (e.g. `en`, `ja`, `ko`) the
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
    /// extension so delete / space can swap on the bottom row.
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

    /// Typing-grid haptic strength (off / light / strong). Default is light.
    @Published public var keyboardHapticIntensity: KeyboardHapticIntensity {
        didSet {
            guard !isApplyingConfiguration,
                  keyboardHapticIntensity != configuration.keyboardHapticIntensity else { return }
            configuration.keyboardHapticIntensity = keyboardHapticIntensity
            persistConfiguration(postConfigChanged: true)
        }
    }

    /// Controls whether fun styles use the full safety envelope or the
    /// formatting-only high-strength path.
    @Published public var polishIntensity: PolishIntensity {
        didSet {
            guard !isApplyingConfiguration,
                  polishIntensity != configuration.polishIntensity else { return }
            configuration.polishIntensity = polishIntensity
            persistConfiguration(postConfigChanged: true)
        }
    }

    /// Soft AI-mode answer length preference (short / medium / detailed).
    @Published public var aiResponseLength: AIResponseLength {
        didSet {
            guard !isApplyingConfiguration,
                  aiResponseLength != configuration.aiResponseLength else { return }
            configuration.aiResponseLength = aiResponseLength
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

    /// Enables provider-specific reasoning / thinking controls when the
    /// selected polish LLM supports them.
    @Published public var llmThinkingEnabled: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  llmThinkingEnabled != configuration.llmThinkingEnabled else { return }
            configuration.llmThinkingEnabled = llmThinkingEnabled
            persistConfiguration(postConfigChanged: true)
        }
    }

    /// When enabled, the keyboard records clipboard text into a local history list.
    @Published public var clipboardHistoryEnabled: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  clipboardHistoryEnabled != configuration.clipboardHistoryEnabled else { return }
            configuration.clipboardHistoryEnabled = clipboardHistoryEnabled
            persistConfiguration(postConfigChanged: true)
        }
    }

    /// When enabled (and history is on), show the newest clipboard item as a suggestion strip.
    @Published public var clipboardCandidateBarEnabled: Bool {
        didSet {
            guard !isApplyingConfiguration,
                  clipboardCandidateBarEnabled != configuration.clipboardCandidateBarEnabled else { return }
            configuration.clipboardCandidateBarEnabled = clipboardCandidateBarEnabled
            persistConfiguration(postConfigChanged: true)
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

    /// Retained for storage compatibility; persistent PiP sessions do not expire from inactivity.
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
        if isLocalEngine {
            return isPolishConfigured
        }
        return isASRConfigured && isPolishConfigured
    }

    public var isPolishConfigured: Bool {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !baseURL.isEmpty && !model.isEmpty
    }

    public var isASRConfigured: Bool {
        guard !isLocalEngine else { return true }
        let key = asrApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKey: Bool = {
            if asrProviderId == "volcengine" {
                return VolcengineASRFields.parse(apiKey: key).hasUsableCredentials
            }
            return !key.isEmpty
        }()
        return hasKey
            && (!asrBaseURL.isEmpty || CloudASRModelCatalog.strategy(for: asrProviderId) != .prompt)
    }

    /// On-device ASR only; no cloud API required.
    public var isLocalEngine: Bool { configuration.isLocalEngine }

    /// Polish provider used by the local engine (same Settings selection as cloud polish).
    public var localModeProviderId: String {
        providerId
    }

    private let defaults: UserDefaults
    private var configuration: AppGroupConfiguration
    /// Suppresses `@Published` observer persistence while a complete snapshot
    /// or preset is applied, preventing reentrant writes of partial state.
    private var isApplyingConfiguration = false
    private var isSyncingProviderAPIKey = false
    private var isSyncingASRProviderAPIKey = false

    public init(defaults: UserDefaults? = nil) {
        guard let resolvedDefaults = defaults ?? AppGroup.defaultsIfAvailable else {
            preconditionFailure(
                "ProviderConfig requires App Group or injected UserDefaults — " +
                "check AppGroup.isAvailable before constructing."
            )
        }
        self.defaults = resolvedDefaults
        self.configuration = AppGroupConfiguration.load(fromAvailable: resolvedDefaults)

        // Fresh app container (reinstall after delete): wipe stale Keychain
        // onboarding so the welcome flow shows again. Reboot races still use
        // Keychain restore when the install identity already exists.
        let isFreshInstall = Keychain.beginInstallIdentityIfNeeded()
        if isFreshInstall {
            configuration.hasCompletedOnboarding = false
            resolvedDefaults.set(false, forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding)
            OSGLog.config.info("[onboarding] init: fresh install → force hasCompletedOnboarding=false")
        } else {
            // Onboarding completion must survive a device reboot. App Group
            // UserDefaults can transiently read empty right after boot, which would
            // falsely re-show onboarding. Trust the durable Keychain marker when the
            // App Group value looks unset, and backfill it once the App Group value
            // is confirmed true (covers users onboarded before this safeguard).
            let appGroupOnboarding = configuration.hasCompletedOnboarding
            let keychainOnboarding = Keychain.hasCompletedOnboarding()
            // Distinguish "key absent" (nil → plist not loaded / data-protection race)
            // from "key present == false" (something actually wrote false).
            let rawKeyPresent = resolvedDefaults.object(
                forKey: AppGroupConfiguration.Keys.hasCompletedOnboarding
            ) != nil
            OSGLog.config.info(
                "[onboarding] init: appGroup=\(appGroupOnboarding, privacy: .public) (keyPresent=\(rawKeyPresent, privacy: .public)), keychain=\(keychainOnboarding, privacy: .public)"
            )
            if appGroupOnboarding {
                Keychain.setOnboardingCompleted(true)
            } else if keychainOnboarding {
                configuration.hasCompletedOnboarding = true
                OSGLog.config.info(
                    "[onboarding] init: App Group read false but Keychain true → restored to true"
                )
            }
        }
        let finalOnboarding = configuration.hasCompletedOnboarding
        OSGLog.config.info("[onboarding] init: final=\(finalOnboarding, privacy: .public)")

        isApplyingConfiguration = true
        providerId = configuration.providerId
        baseURL = configuration.baseURL
        apiKey = configuration.apiKey
        model = configuration.model
        asrProviderId = configuration.asrProviderId
        asrBaseURL = configuration.asrBaseURL
        asrModel = configuration.asrModel
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
        keyboardHapticIntensity = configuration.keyboardHapticIntensity
        polishIntensity = configuration.polishIntensity
        aiResponseLength = configuration.aiResponseLength
        llmThinkingEnabled = configuration.llmThinkingEnabled
        clipboardHistoryEnabled = configuration.clipboardHistoryEnabled
        clipboardCandidateBarEnabled = configuration.clipboardCandidateBarEnabled
        flowSkipAppSwitch = configuration.flowSkipAppSwitch
        flowInactivityDuration = configuration.flowInactivityDuration
        localASRCustomLanguageModelEnabled = configuration.localASRCustomLanguageModelEnabled
        isSyncingProviderAPIKey = true
        apiKey = configuration.apiKey
        isSyncingProviderAPIKey = false
        isSyncingASRProviderAPIKey = true
        asrApiKey = configuration.asrApiKey
        isSyncingASRProviderAPIKey = false
        isApplyingConfiguration = false
    }

    public func reset() {
        isApplyingConfiguration = true
        let polishPreset = LLMProvider.provider(id: AppGroupConfiguration.defaultPolishProviderId)
        let asrPreset = LLMProvider.provider(id: AppGroupConfiguration.defaultCloudASRProviderId)
        providerId = polishPreset.id
        baseURL = polishPreset.defaultBaseURL
        apiKey = ""
        model = polishPreset.defaultModel
        asrProviderId = asrPreset.id
        asrBaseURL = asrPreset.defaultBaseURL
        asrModel = CloudASRModelCatalog.defaultModel(for: asrPreset.id)
        asrApiKey = ""
        handednessPreference = .left
        keyboardHapticIntensity = .default
        polishIntensity = .default
        aiResponseLength = .default
        localASRCustomLanguageModelEnabled = true
        llmThinkingEnabled = false
        clipboardHistoryEnabled = false
        clipboardCandidateBarEnabled = false
        hasAcknowledgedCloudSharing = false
        configuration.providerId = polishPreset.id
        configuration.baseURL = polishPreset.defaultBaseURL
        configuration.model = polishPreset.defaultModel
        configuration.asrProviderId = asrPreset.id
        configuration.asrBaseURL = asrPreset.defaultBaseURL
        configuration.asrModel = CloudASRModelCatalog.defaultModel(for: asrPreset.id)
        configuration.handednessPreference = .left
        configuration.keyboardHapticIntensity = .default
        configuration.polishIntensity = .default
        configuration.aiResponseLength = .default
        configuration.localASRCustomLanguageModelEnabled = true
        configuration.llmThinkingEnabled = false
        configuration.clipboardHistoryEnabled = false
        configuration.clipboardCandidateBarEnabled = false
        configuration.hasAcknowledgedCloudSharing = false
        defaults.removeObject(forKey: AppGroupConfiguration.Keys.microphonePriority)
        isApplyingConfiguration = false
        persistConfiguration()
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
        asrProviderId = fresh.asrProviderId
        asrBaseURL = fresh.asrBaseURL
        asrModel = fresh.asrModel
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
        keyboardHapticIntensity = fresh.keyboardHapticIntensity
        polishIntensity = fresh.polishIntensity
        aiResponseLength = fresh.aiResponseLength
        llmThinkingEnabled = fresh.llmThinkingEnabled
        clipboardHistoryEnabled = fresh.clipboardHistoryEnabled
        clipboardCandidateBarEnabled = fresh.clipboardCandidateBarEnabled
        flowSkipAppSwitch = fresh.flowSkipAppSwitch
        flowInactivityDuration = fresh.flowInactivityDuration
        localASRCustomLanguageModelEnabled = fresh.localASRCustomLanguageModelEnabled
        isSyncingProviderAPIKey = true
        apiKey = fresh.apiKey
        isSyncingProviderAPIKey = false
        isSyncingASRProviderAPIKey = true
        asrApiKey = fresh.asrApiKey
        isSyncingASRProviderAPIKey = false
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

    public func applyAsr(preset: LLMProvider) {
        isApplyingConfiguration = true
        asrProviderId = preset.id
        if !preset.defaultBaseURL.isEmpty {
            asrBaseURL = preset.defaultBaseURL
        }
        asrModel = CloudASRModelCatalog.defaultModel(for: preset.id)
        configuration.asrProviderId = asrProviderId
        configuration.asrBaseURL = asrBaseURL
        configuration.asrModel = asrModel
        isSyncingASRProviderAPIKey = true
        asrApiKey = configuration.asrApiKey
        isSyncingASRProviderAPIKey = false
        isApplyingConfiguration = false
        persistConfiguration()
    }
}
