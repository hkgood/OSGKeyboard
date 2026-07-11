// AppGroupStore.swift
// OSGKeyboard · Shared
//
// Thin read/write facade over `AppGroupConfiguration` for the keyboard
// extension (no SwiftUI) and other non-ObservableObject call sites.
//
// `apiKey` is NOT stored in UserDefaults — see `Keychain.swift`.

import Foundation

public struct AppGroupStore: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
            return
        }
        if let available = AppGroup.defaultsIfAvailable {
            self.defaults = available
            return
        }
        #if os(iOS)
        // iOS app + keyboard extension MUST share the App Group suite; a
        // silent `.standard` fallback would desync them. Keep this a hard
        // failure so a provisioning mistake is impossible to miss.
        #if DEBUG
        fatalError("App Group unavailable — inject UserDefaults in tests or fix entitlements.")
        #else
        fatalError("App Group unavailable.")
        #endif
        #else
        // macOS is a standalone menu-bar app with no keyboard extension to
        // stay in sync with, so a missing App Group container is expected;
        // fall back to the app's standard defaults.
        self.defaults = .standard
        #endif
    }

    private var configuration: AppGroupConfiguration {
        AppGroupConfiguration.load(fromAvailable: defaults)
    }

    private func mutateConfiguration(_ transform: (inout AppGroupConfiguration) -> Void) {
        var config = AppGroupConfiguration.load(fromAvailable: defaults)
        transform(&config)
        config.save(to: defaults)
    }

    // MARK: - Reads

    public var providerId: String { configuration.providerId }
    public var baseURL: String { configuration.baseURL }
    public var apiKey: String { configuration.apiKey }
    public var model: String { configuration.model }
    public var asrProviderId: String { configuration.asrProviderId }
    public var asrBaseURL: String { configuration.resolvedASRBaseURL }
    public var asrApiKey: String { configuration.asrApiKey }
    public var asrModel: String { configuration.resolvedASRModel }
    public var modeId: String { configuration.modeId }
    public var localeId: String { configuration.localeId }
    public var engineMode: String { configuration.engineMode }
    public var uiLanguage: AppUILanguage { configuration.uiLanguage }
    public var translationEnabled: Bool { configuration.translationEnabled }
    public var translationTargetLocaleId: String { configuration.translationTargetLocaleId }
    public var handednessPreference: HandednessPreference { configuration.handednessPreference }
    public var cursorDragNavigationEnabled: Bool { configuration.cursorDragNavigationEnabled }
    public var polishIntensity: PolishIntensity { configuration.polishIntensity }
    public var llmThinkingEnabled: Bool { configuration.llmThinkingEnabled }
    public var isTranslationEffective: Bool { configuration.isTranslationEffective }
    public var isLocalEngine: Bool { configuration.isLocalEngine }
    public var polishModeForPipeline: PolishingService.PolishMode { configuration.polishModeForPipeline }
    public var polishProviderIdOverride: String? { configuration.polishProviderIdOverride }
    public var isCloudAPIKeyMissingForVoiceInput: Bool { configuration.isCloudAPIKeyMissingForVoiceInput }
    public var localASRCustomLanguageModelEnabled: Bool { configuration.localASRCustomLanguageModelEnabled }

    /// Whether the keyboard top-bar translation chip should render.
    public var isTranslationChipVisible: Bool { true }

    // MARK: - Writes

    public func setModeId(_ id: String) {
        mutateConfiguration { $0.modeId = id }
    }

    public func setLocaleId(_ id: String) {
        mutateConfiguration { $0.localeId = id }
    }

    public func setEngineMode(_ mode: String) {
        mutateConfiguration { $0.engineMode = mode }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setUILanguage(_ language: AppUILanguage) {
        mutateConfiguration { $0.uiLanguage = language }
    }

    public func setTranslationEnabled(_ enabled: Bool) {
        setTranslationTargetLocaleId(
            enabled ? TranslationLanguageCatalog.defaultLocaleId : TranslationLanguageCatalog.offLocaleId
        )
    }

    public func setTranslationTargetLocaleId(_ id: String) {
        mutateConfiguration { $0.translationTargetLocaleId = id }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setHandednessPreference(_ preference: HandednessPreference) {
        mutateConfiguration { $0.handednessPreference = preference }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setCursorDragNavigationEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.cursorDragNavigationEnabled = enabled }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setPolishIntensity(_ intensity: PolishIntensity) {
        mutateConfiguration { $0.polishIntensity = intensity }
    }

    public func setLLMThinkingEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.llmThinkingEnabled = enabled }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setLocalASRCustomLanguageModelEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.localASRCustomLanguageModelEnabled = enabled }
    }

    public var hasCompletedOnboarding: Bool {
        get { configuration.hasCompletedOnboarding }
        set { setHasCompletedOnboarding(newValue) }
    }

    public var onboardingPage: Int {
        get { configuration.onboardingPage }
        set { setOnboardingPage(newValue) }
    }

    public func setHasCompletedOnboarding(_ completed: Bool) {
        mutateConfiguration { config in
            config.hasCompletedOnboarding = completed
            if completed {
                config.onboardingPage = 0
            }
        }
        // Mirror to the reboot-durable Keychain marker (keyboard-side completion).
        Keychain.setOnboardingCompleted(completed)
    }

    public func setOnboardingPage(_ page: Int) {
        mutateConfiguration { $0.onboardingPage = page }
    }

    // MARK: - Detected app context

    public var detectedAppContext: (context: AppContext, observedAt: Date)? {
        configuration.detectedAppContext(from: defaults)
    }

    public func setDetectedAppContext(_ context: AppContext, at date: Date = Date()) {
        var config = configuration
        config.setDetectedAppContext(context, at: date, to: defaults)
    }

    // MARK: - Personal dictionary

    public var personalDictionary: PersonalDictionary {
        get { configuration.personalDictionary }
        set { setPersonalDictionary(newValue) }
    }

    public func setPersonalDictionary(_ dictionary: PersonalDictionary) {
        mutateConfiguration { $0.personalDictionary = dictionary }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func deletePersonalDictionaryEntry(id: UUID, at date: Date = Date()) {
        mutateConfiguration { config in
            config.personalDictionary.entries.removeAll { $0.id == id }
            config.personalDictionary.deletedEntryIDs[id] = date
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public var personalDictionaryICloudSyncEnabled: Bool {
        get { configuration.personalDictionaryICloudSyncEnabled }
        set { setPersonalDictionaryICloudSyncEnabled(newValue) }
    }

    public func setPersonalDictionaryICloudSyncEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.personalDictionaryICloudSyncEnabled = enabled }
    }

    public var settingsICloudSyncEnabled: Bool {
        get { configuration.settingsICloudSyncEnabled }
        set { setSettingsICloudSyncEnabled(newValue) }
    }

    public func setSettingsICloudSyncEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.settingsICloudSyncEnabled = enabled }
    }

    /// Timestamp of the last settings blob applied from iCloud KVS.
    public var settingsCloudUpdatedAt: Date? {
        let raw = defaults.double(forKey: AppGroupConfiguration.Keys.settingsCloudUpdatedAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    // MARK: - Client

    public func makeClient() -> LLMClient {
        configuration.makeClient()
    }
}
