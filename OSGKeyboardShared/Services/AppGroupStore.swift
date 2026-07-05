// AppGroupStore.swift
// OSGKeyboard · Shared
//
// Convenience wrapper around App Group UserDefaults for non-Published reads.
// Used by the keyboard extension (no SwiftUI) to read config without
// instantiating an ObservableObject.
//
// `apiKey` is NOT read from UserDefaults — see `Keychain.swift`. We
// share access between the host app and the keyboard extension via a
// shared keychain-access-group declared in both targets' entitlements.

import Foundation

public struct AppGroupStore: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
            return
        }
        // Never hard-crash on implicit construction sites (e.g. default
        // service initializers). If App Group is unavailable, use .standard
        // so callers can still surface a user-facing setup error.
        self.defaults = AppGroup.isAvailable ? AppGroup.defaults : .standard
    }

    // MARK: - Keys

    private enum Key {
        static let providerId      = "config.providerId"
        static let baseURL         = "config.baseURL"
        static let model           = "config.model"
        static let modeId          = "config.modeId"
        static let localeId        = "config.localeId"
        static let engineMode       = "config.engineMode"
        static let localASRBackend  = "config.localASRBackend"
        static let uiLanguage       = "config.uiLanguage"
        // v0.2.0: opt-in cloud polish step after local-mode ASR.
        static let localModeCloudPolishEnabled = "config.localModeCloudPolishEnabled"
        // v0.2.1 follow-up: `config.translationEnabled` was *removed* as a
        // persisted key — translation is derived from the target locale
        // id. New code should only write/read `translationTargetLocaleId`;
        // the `translationEnabled` Bool accessor below is kept as a
        // computed shim for source compatibility.
        static let translationTargetLocaleId = "config.translationTargetLocaleId"
        static let handednessPreference = "config.handednessPreference"
        // Drag pads beside the mic move the caret like arrow keys.
        static let cursorDragNavigationEnabled = "config.cursorDragNavigationEnabled"
        // v0.3.0: polish intensity (off / light / medium / heavy).
        static let polishIntensity = "config.polishIntensity"
        // v0.3.0: last app context detected by the keyboard extension.
        // Reused across calls within a 30-minute window so the LLM
        // prompt remains consistent during a single typing session.
        static let detectedAppContext = "config.detectedAppContext"
        static let detectedAppContextAt = "config.detectedAppContextAt"
        // v0.3.0: personal dictionary — JSON-encoded `PersonalDictionary`.
        static let personalDictionary = "config.personalDictionary.v1"
    }

    // MARK: - Reads

    public var providerId: String {
        defaults.string(forKey: Key.providerId) ?? "openai"
    }

    public var baseURL: String {
        defaults.string(forKey: Key.baseURL) ?? LLMProvider.provider(id: providerId).defaultBaseURL
    }

    /// API key lives in the Keychain (cross-process, encrypted at rest).
    /// Returns "" when nothing is stored so the LLMClient can surface a
    /// `noAPIKey` error rather than firing off an obviously-bad request.
    public var apiKey: String {
        Keychain.apiKey(for: providerId) ?? ""
    }

    public var model: String {
        defaults.string(forKey: Key.model) ?? LLMProvider.provider(id: providerId).defaultModel
    }

    public var modeId: String {
        defaults.string(forKey: Key.modeId) ?? "polish"
    }

    public var localeId: String {
        defaults.string(forKey: Key.localeId) ?? "auto"
    }

    /// "local" → on-device ASR only (raw transcript delivery).
    /// "cloud" → ASR + LLM polish (default behaviour).
    public var engineMode: String {
        defaults.string(forKey: Key.engineMode) ?? "cloud"
    }

    /// Which on-device ASR engine backs the "local" engine mode. Falls
    /// back to the iOS SpeechAnalyzer path so legacy installs (which
    /// never wrote this key) keep working.
    public var localASRBackend: LocalASRBackend {
        let raw = defaults.string(forKey: Key.localASRBackend) ?? LocalASRBackend.speechAnalyzer.rawValue
        return LocalASRBackend(rawValue: raw) ?? .speechAnalyzer
    }

    /// v0.2.0: whether the local engine should route its transcript
    /// through the configured cloud LLM (DeepSeek by default) before
    /// insertion. Defaults to `false`; the keyboard extension reads
    /// this so Flow sessions honour the toggle.
    public var localModeCloudPolishEnabled: Bool {
        guard defaults.object(forKey: Key.localModeCloudPolishEnabled) != nil else {
            return false
        }
        return defaults.bool(forKey: Key.localModeCloudPolishEnabled)
    }

    /// Host-app UI language override (`auto` / `en` / `zh-Hans`).
    public var uiLanguage: AppUILanguage {
        AppUILanguage.fromStored(defaults.string(forKey: Key.uiLanguage))
    }

    /// v0.2.1 follow-up: derived — translation is on iff a target locale
    /// has been selected. The `translationTargetLocaleId` getter below
    /// is the source of truth; this property exists for backwards
    /// compatibility with call sites that read `store.translationEnabled`.
    public var translationEnabled: Bool {
        translationTargetLocaleId != TranslationLanguageCatalog.offLocaleId
    }

    /// v0.2.1: target locale id the translate-and-polish prompt should
    /// produce (e.g. `"en"`, `"ja"`). Defaults to `offLocaleId` ("off")
    /// when nothing is stored, matching the picker / chip UX where the
    /// user has to actively pick a language to turn translation on.
    public var translationTargetLocaleId: String {
        defaults.string(forKey: Key.translationTargetLocaleId)
            ?? TranslationLanguageCatalog.offLocaleId
    }

    /// Bottom-row key order on the keyboard extension.
    public var handednessPreference: HandednessPreference {
        HandednessPreference.fromStored(defaults.string(forKey: Key.handednessPreference))
    }

    /// Press-and-drag pads beside the mic for four-way caret movement.
    /// Defaults to `true` for new installs.
    public var cursorDragNavigationEnabled: Bool {
        guard defaults.object(forKey: Key.cursorDragNavigationEnabled) != nil else {
            return true
        }
        return defaults.bool(forKey: Key.cursorDragNavigationEnabled)
    }

    // MARK: - Writes

    public func setModeId(_ id: String) {
        defaults.set(id, forKey: Key.modeId)
    }

    public func setLocaleId(_ id: String) {
        defaults.set(id, forKey: Key.localeId)
    }

    public func setEngineMode(_ mode: String) {
        defaults.set(mode, forKey: Key.engineMode)
    }

    public func setLocalASRBackend(_ backend: LocalASRBackend) {
        defaults.set(backend.rawValue, forKey: Key.localASRBackend)
    }

    public func setUILanguage(_ language: AppUILanguage) {
        defaults.set(language.rawValue, forKey: Key.uiLanguage)
    }

    /// v0.2.1 follow-up: kept for source compatibility with callers that
    /// still pass a Bool (e.g. older tests, any leftover bridge code).
    /// `enabled == true` selects `defaultLocaleId` ("en") as a sensible
    /// on-ramp target; `enabled == false` resets to `offLocaleId`.
    /// The keyboard chip / pipeline now write the locale id directly
    /// via `setTranslationTargetLocaleId`, which is the preferred path.
    public func setTranslationEnabled(_ enabled: Bool) {
        defaults.set(
            enabled ? TranslationLanguageCatalog.defaultLocaleId : TranslationLanguageCatalog.offLocaleId,
            forKey: Key.translationTargetLocaleId
        )
    }

    /// v0.2.1: persist target locale id (e.g. `"en"`, `"ja"`, or
    /// `TranslationLanguageCatalog.offLocaleId`). The keyboard
    /// extension reads this on every `load()` and `refreshRuntimeFlags()`
    /// so the chip reflects the latest value without a host-app
    /// round-trip.
    public func setTranslationTargetLocaleId(_ id: String) {
        defaults.set(id, forKey: Key.translationTargetLocaleId)
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setHandednessPreference(_ preference: HandednessPreference) {
        defaults.set(preference.rawValue, forKey: Key.handednessPreference)
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setCursorDragNavigationEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.cursorDragNavigationEnabled)
        AppGroupConfigDarwin.postConfigChanged()
    }

    /// Whether ASR output should be sent through the LLM polish step.
    /// Both engines always run polish after ASR completes (chunked
    /// pipeline stitches first). Ultra-short structure-free utterances
    /// may skip the LLM inside `PolishingService`.
    public var shouldRunCloudLLMStep: Bool { true }

    /// Whether translate-and-polish should run (vs polish-only).
    public var isTranslationEffective: Bool {
        translationEnabled
    }

    /// Whether the keyboard top-bar translation chip should render.
    public var isTranslationChipVisible: Bool { true }

    /// Cloud engine requires a provider-specific API key before the user
    /// can start voice input. Local engine uses the built-in DeepSeek path.
    public var isCloudAPIKeyMissingForVoiceInput: Bool {
        guard engineMode == "cloud" else { return false }
        return apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Polish vs translate-and-polish for the active pipeline.
    public var polishModeForPipeline: PolishingService.PolishMode {
        isTranslationEffective
            ? .translate(targetLocaleId: translationTargetLocaleId)
            : .polish
    }

    /// Local engine pins the LLM step to DeepSeek; cloud uses the
    /// user's configured provider.
    public var polishProviderIdOverride: String? {
        engineMode == "local" ? "deepseek" : nil
    }

    // MARK: - Polish settings (v0.3.0+)

    /// How aggressively the LLM should rewrite the ASR transcript.
    /// Defaults to `medium` for new installs.
    public var polishIntensity: PolishIntensity {
        guard let raw = defaults.string(forKey: Key.polishIntensity) else {
            return .default
        }
        let resolved = PolishIntensity.resolve(storedRawValue: raw)
        if raw == PolishIntensity.legacyOffRawValue {
            defaults.set(resolved.rawValue, forKey: Key.polishIntensity)
        }
        return resolved
    }

    public func setPolishIntensity(_ intensity: PolishIntensity) {
        defaults.set(intensity.rawValue, forKey: Key.polishIntensity)
    }

    // MARK: - Onboarding (v0.3.0+)
    //
    // Mirrored from `ProviderConfig` so the keyboard extension's
    // overlay can read / write the same source of truth without
    // instantiating the main-app config (which would drag in
    // SwiftUI / Combine and fight the keyboard's main-thread budget).

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "config.hasCompletedOnboarding") }
        set { defaults.set(newValue, forKey: "config.hasCompletedOnboarding") }
    }

    public var onboardingPage: Int {
        get { defaults.integer(forKey: "config.onboardingPage") }
        set { defaults.set(newValue, forKey: "config.onboardingPage") }
    }

    public func setHasCompletedOnboarding(_ completed: Bool) {
        defaults.set(completed, forKey: "config.hasCompletedOnboarding")
    }

    public func setOnboardingPage(_ page: Int) {
        defaults.set(page, forKey: "config.onboardingPage")
    }

    // MARK: - Detected app context (v0.3.0+)

    /// Last app context the keyboard extension detected for this
    /// user, plus the timestamp it was observed. Callers should
    /// treat values older than 30 minutes as stale.
    public var detectedAppContext: (context: AppContext, observedAt: Date)? {
        guard let raw = defaults.string(forKey: Key.detectedAppContext),
              let value = AppContext(rawValue: raw)
        else { return nil }
        let timestamp = defaults.object(forKey: Key.detectedAppContextAt) as? Date ?? .distantPast
        return (value, timestamp)
    }

    public func setDetectedAppContext(_ context: AppContext, at date: Date = Date()) {
        defaults.set(context.rawValue, forKey: Key.detectedAppContext)
        defaults.set(date, forKey: Key.detectedAppContextAt)
    }

    // MARK: - Personal dictionary (v0.3.0+)

    /// Personal dictionary persisted in the App Group so both the
    /// main app's Settings UI and the keyboard extension's LLM call
    /// read the same source of truth. Returns an empty dictionary
    /// when nothing is stored (and when the stored JSON is corrupt —
    /// failing closed is safer than crashing the keyboard).
    public var personalDictionary: PersonalDictionary {
        get {
            guard let data = defaults.data(forKey: Key.personalDictionary) else {
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
                        defaults.set(migrated, forKey: Key.personalDictionary)
                    }
                }
                return dictionary
            } catch {
                #if DEBUG
                print("⚠️ [AppGroupStore] personalDictionary decode failed: \(error)")
                #endif
                return .empty
            }
        }
        set {
            setPersonalDictionary(newValue)
        }
    }

    public func setPersonalDictionary(_ dictionary: PersonalDictionary) {
        do {
            let data = try JSONEncoder().encode(dictionary)
            defaults.set(data, forKey: Key.personalDictionary)
        } catch {
            #if DEBUG
            print("⚠️ [AppGroupStore] personalDictionary encode failed: \(error)")
            #endif
        }
    }

    // MARK: - Client

    public func makeClient() -> LLMClient {
        OpenAICompatibleClient(
            baseURL: baseURL,
            apiKey: apiKey,
            model: model
        )
    }
}
