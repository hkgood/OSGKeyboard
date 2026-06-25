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

    private enum Key {
        static let providerId      = "config.providerId"
        static let baseURL         = "config.baseURL"
        // Legacy: apiKey used to live in UserDefaults before the
        // migration. We still read it once (see init below) and then
        // delete the entry, but no other code path touches this key.
        static let apiKeyLegacy    = "config.apiKey"
        static let model           = "config.model"
        static let systemPrompt    = "config.systemPrompt"
        static let modeId          = "config.modeId"
        static let localeId        = "config.localeId"
        static let engineMode       = "config.engineMode"
        static let hasCompletedOnboarding = "config.hasCompletedOnboarding"
        static let onboardingPage         = "config.onboardingPage"
        static let hasAcknowledgedCloudSharing = "config.hasAcknowledgedCloudSharing"
        // Which on-device ASR engine to use when `engineMode == "local"`.
        // Persisted in the App Group so the keyboard can read the
        // selection even though it never instantiates the backend itself.
        static let localASRBackend = "config.localASRBackend"
        static let uiLanguage = "config.uiLanguage"
        // v0.2.0: optional cloud polish step after on-device ASR finishes
        // in the local engine. Default `false` — keeps the local engine
        // truly local unless the user explicitly opts in.
        static let localModeCloudPolishEnabled = "config.localModeCloudPolishEnabled"
        // v0.2.1: optional translation step after ASR. The
        // post-ASR transcript is routed through the same LLM with a
        // translate-and-polish prompt targeting `translationTargetLocaleId`.
        // Mutually exclusive with the local-only promise — see `TranslationPolicy`.
        //
        // v0.2.1 follow-up: `config.translationEnabled` was *removed*
        // as a persisted key — translation is now derived from
        // `translationTargetLocaleId` (== offLocaleId means "off"). The
        // store still tolerates legacy reads of the old key so users
        // who upgraded from a build that wrote it don't see a flash of
        // "on" state during init, but new writes never touch the key.
        static let translationTargetLocaleId = "config.translationTargetLocaleId"
    }

    @Published public var providerId: String {
        didSet { defaults.set(providerId, forKey: Key.providerId) }
    }
    @Published public var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Key.baseURL) }
    }
    @Published public var apiKey: String {
        didSet {
            // Skip the round-trip on init — we read from Keychain and
            // writing the same value back is wasteful.
            guard oldValue != apiKey else { return }
            do {
                try Keychain.setAPIKey(apiKey)
            } catch {
                #if DEBUG
                print("⚠️ [OSGKeyboard] Keychain write failed: \(error)")
                #endif
            }
        }
    }
    @Published public var model: String {
        didSet { defaults.set(model, forKey: Key.model) }
    }
    @Published public var systemPrompt: String {
        didSet { defaults.set(systemPrompt, forKey: Key.systemPrompt) }
    }
    @Published public var modeId: String {
        didSet { defaults.set(modeId, forKey: Key.modeId) }
    }
    @Published public var localeId: String {
        didSet { defaults.set(localeId, forKey: Key.localeId) }
    }
    /// "local" → on-device ASR only (raw transcript delivery).
    /// "cloud" → ASR + LLM polish (always on; modeId kept for compatibility).
    @Published public var engineMode: String {
        didSet { defaults.set(engineMode, forKey: Key.engineMode) }
    }
    @Published public var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
            if hasCompletedOnboarding {
                onboardingPage = 0
            }
        }
    }
    /// Persisted onboarding step so returning from Settings does not reset progress.
    @Published public var onboardingPage: Int {
        didSet { defaults.set(onboardingPage, forKey: Key.onboardingPage) }
    }
    /// User confirmed that Cloud polish sends transcripts to their configured third-party API.
    @Published public var hasAcknowledgedCloudSharing: Bool {
        didSet { defaults.set(hasAcknowledgedCloudSharing, forKey: Key.hasAcknowledgedCloudSharing) }
    }
    /// Which on-device ASR engine backs the "local" engine mode. Only
    /// consulted when `isLocalEngine == true`; the cloud engine always
    /// uses `SpeechAnalyzer`.
    @Published public var localASRBackend: LocalASRBackend {
        didSet { defaults.set(localASRBackend.rawValue, forKey: Key.localASRBackend) }
    }
    /// When `engineMode == "local"`, optionally route the ASR transcript
    /// through the user's configured LLM (DeepSeek by default) before
    /// inserting at the cursor. The polish step runs through the same
    /// `LLMClient` + `PolishingService` stack the cloud engine uses.
    ///
    /// Defaults to `false` — the local engine is ASR-only out of the
    /// box. Users opt in from Settings when the iOS ASR output isn't
    /// strong enough (noisy far-field audio, dialectal Chinese, etc.).
    @Published public var localModeCloudPolishEnabled: Bool {
        didSet { defaults.set(localModeCloudPolishEnabled, forKey: Key.localModeCloudPolishEnabled) }
    }
    /// Host-app UI language. Also mirrored to the App Group for the keyboard extension.
    @Published public var uiLanguage: AppUILanguage {
        didSet { defaults.set(uiLanguage.rawValue, forKey: Key.uiLanguage) }
    }
    /// v0.2.1: whether to translate the transcript into
    /// `translationTargetLocaleId` before insertion. **Derived** —
    /// translation is on iff the user has selected a target locale
    /// (i.e. the persisted id is anything other than
    /// `TranslationLanguageCatalog.offLocaleId`). Default off.
    ///
    /// This used to be a stored `@Published var ... { didSet }` but the
    /// chip / picker now writes the locale directly; collapsing the
    /// pair into one field removes the "two writes out of sync" bug
    /// surface entirely.
    public var translationEnabled: Bool {
        translationTargetLocaleId != TranslationLanguageCatalog.offLocaleId
    }
    /// v0.2.1: BCP-47-ish target language id (e.g. `en`, `ja`, `ko`) the
    /// translate-and-polish prompt should produce. Default `"off"` —
    /// translation is opt-in. Persisted in the App Group so the keyboard
    /// extension can honour it (and so the chip on the keyboard reflects
    /// the user's choice without a host-app round-trip).
    @Published public var translationTargetLocaleId: String {
        didSet { defaults.set(translationTargetLocaleId, forKey: Key.translationTargetLocaleId) }
    }

    /// v0.2.1 follow-up: with the local engine's translate-and-polish
    /// path now real (see `localModeProviderId`), `translationEnabled`
    /// alone is enough to decide whether the pipeline should translate.
    /// Row visibility (`isTranslationRowVisible`) already gates the UI
    /// on engines that can actually run the step, so we don't need to
    /// re-check `engineMode` here.
    public var isTranslationEffective: Bool {
        translationEnabled
    }

    /// v0.2.1 follow-up: row visibility predicate. Both engines can
    /// now run the cloud translate-and-polish step (the local engine
    /// routes through DeepSeek via `localModeProviderId`), so the row
    /// is shown whenever an engine mode is selected.
    public var isTranslationRowVisible: Bool {
        engineMode == "local" || engineMode == "cloud"
    }

    public var isConfigured: Bool {
        // Local engine (on-device ASR only) doesn't need an API key,
        // base URL, or model — the LLM round-trip is skipped entirely.
        // Treat it as always-configured so onboarding's "Next" button
        // enables the moment the user picks the local path, instead
        // of forcing them to fill in cloud fields they won't use.
        if isLocalEngine { return true }
        return !baseURL.isEmpty && !apiKey.isEmpty && !model.isEmpty
    }

    /// On-device ASR only; no cloud API required.
    public var isLocalEngine: Bool { engineMode == "local" }

    /// Whether a transcript produced by the local engine should be
    /// sent through the cloud LLM polish step before insertion.
    ///
    /// v0.2.0: the local engine defaults to ASR-only. When the user
    /// enables "Cloud polish after ASR" (`localModeCloudPolishEnabled`)
    /// we route the transcript through the configured LLM (DeepSeek by
    /// default in local mode) — same `PolishingService` code path the
    /// cloud engine uses.
    ///
    /// If the user hasn't entered an API key we can't run the polish
    /// step; callers should check `Keychain.apiKey()` before invoking.
    public var shouldPolishLocalTranscript: Bool {
        isLocalEngine && localModeCloudPolishEnabled
    }

    /// v0.2.1 follow-up: when the local engine is using the cloud-
    /// polish step, route the call through DeepSeek — cheap, strong
    /// on Chinese, and the right default for the on-device ASR
    /// transcript. Other engines honor the user's configured
    /// `providerId` unchanged so cloud users keep their preferred
    /// vendor (OpenAI / Anthropic / Zhipu / etc).
    public var localModeProviderId: String {
        isLocalEngine ? "deepseek" : providerId
    }

    /// The system prompt the user *sees* in the editor — fall back to the
    /// provider-aware default from `AppGroupStore` when nothing is set.
    public var defaultSystemPrompt: String {
        AppGroupStore.defaultSystemPrompt(for: providerId)
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        let resolvedDefaults: UserDefaults = defaults ?? (AppGroup.isAvailable ? AppGroup.defaults : .standard)
        self.defaults = resolvedDefaults
        let pid = resolvedDefaults.string(forKey: Key.providerId) ?? "openai"
        let preset = LLMProvider.provider(id: pid)
        self.providerId   = pid
        self.baseURL      = resolvedDefaults.string(forKey: Key.baseURL)    ?? preset.defaultBaseURL

        // Resolve the API key with a one-shot migration from the legacy
        // UserDefaults slot. After this runs once, `Key.apiKeyLegacy`
        // is empty in the suite and all subsequent reads go through the
        // Keychain.
        self.apiKey = ProviderConfig.resolveAPIKey(defaults: resolvedDefaults)

        self.model        = resolvedDefaults.string(forKey: Key.model)      ?? preset.defaultModel
        self.systemPrompt = resolvedDefaults.string(forKey: Key.systemPrompt)
            ?? AppGroupStore.defaultSystemPrompt(for: pid)
        self.modeId          = resolvedDefaults.string(forKey: Key.modeId)     ?? "polish"
        self.localeId        = resolvedDefaults.string(forKey: Key.localeId)   ?? "auto"
        self.engineMode       = resolvedDefaults.string(forKey: Key.engineMode) ?? "cloud"
        self.hasCompletedOnboarding = resolvedDefaults.bool(forKey: Key.hasCompletedOnboarding)
        let savedPage = resolvedDefaults.integer(forKey: Key.onboardingPage)
        self.onboardingPage = savedPage > 0 ? savedPage : 0
        self.hasAcknowledgedCloudSharing = resolvedDefaults.bool(forKey: Key.hasAcknowledgedCloudSharing)
        // Tolerate missing / unknown raw values (e.g. an enum case that
        // was renamed in a later build) by falling back to the default
        // rather than crashing inside `RawRepresentable.init`.
        let rawBackend = resolvedDefaults.string(forKey: Key.localASRBackend) ?? LocalASRBackend.speechAnalyzer.rawValue
        self.localASRBackend = LocalASRBackend(rawValue: rawBackend) ?? .speechAnalyzer
        // v0.2.0: local-mode cloud polish toggle. Defaults off; users
        // opt in from Settings when iOS ASR is too lossy for their
        // environment. `object(forKey:) == nil` covers fresh installs
        // and upgrades from builds that never wrote the key.
        if resolvedDefaults.object(forKey: Key.localModeCloudPolishEnabled) == nil {
            self.localModeCloudPolishEnabled = false
        } else {
            self.localModeCloudPolishEnabled = resolvedDefaults.bool(forKey: Key.localModeCloudPolishEnabled)
        }
        self.uiLanguage = AppUILanguage.fromStored(
            resolvedDefaults.string(forKey: Key.uiLanguage)
        )
        // v0.2.1 follow-up: `translationEnabled` is now derived from
        // `translationTargetLocaleId` — no separate init read.
        // Default the locale id to `offLocaleId` so existing installs
        // that never picked a target language stay in the "off" state
        // (the previous build's default of `"en"` would silently turn
        // translation on for every upgraded user; off is the safe
        // conservative default that matches the picker / chip UX).
        self.translationTargetLocaleId = resolvedDefaults.string(forKey: Key.translationTargetLocaleId)
            ?? TranslationLanguageCatalog.offLocaleId

        // Cloud no longer exposes off/transcribe; migrate legacy values.
        if self.engineMode == "cloud", self.modeId != "polish" {
            self.modeId = "polish"
        }
    }

    /// Read the API key from the Keychain, falling back to a one-time
    /// migration from the legacy UserDefaults slot.
    private static func resolveAPIKey(defaults: UserDefaults) -> String {
        if let stored = Keychain.apiKey(), !stored.isEmpty {
            return stored
        }
        if let legacy = defaults.string(forKey: Key.apiKeyLegacy),
           !legacy.isEmpty {
            try? Keychain.setAPIKey(legacy)
            defaults.removeObject(forKey: Key.apiKeyLegacy)
            return legacy
        }
        return ""
    }

    public func apply(preset: LLMProvider) {
        // Capture the *previous* provider id BEFORE we mutate, so the
        // system-prompt reset check below can compare against the actual
        // prior default.
        let oldId = providerId
        providerId = preset.id
        if !preset.defaultBaseURL.isEmpty {
            baseURL = preset.defaultBaseURL
        }
        if !preset.defaultModel.isEmpty {
            model = preset.defaultModel
        }
        // When switching providers, reset the system prompt to the new
        // provider's default — otherwise the user is left editing a
        // Chinese prompt on a US-English model.
        if systemPrompt.isEmpty
            || systemPrompt == AppGroupStore.defaultSystemPrompt(for: oldId) {
            systemPrompt = AppGroupStore.defaultSystemPrompt(for: preset.id)
        }
    }

    public func reset() {
        providerId = "openai"
        let preset = LLMProvider.provider(id: "openai")
        baseURL = preset.defaultBaseURL
        apiKey = ""
        model = preset.defaultModel
        systemPrompt = AppGroupStore.defaultSystemPrompt(for: "openai")
        hasAcknowledgedCloudSharing = false
    }
}
