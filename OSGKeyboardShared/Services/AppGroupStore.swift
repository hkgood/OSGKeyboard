// AppGroupStore.swift
// OSGKeyboard · Shared
//
// Thin read/write facade over `AppGroupConfiguration` for the keyboard
// extension (no SwiftUI) and other non-ObservableObject call sites.
//
// `apiKey` is NOT stored in UserDefaults — see `Keychain.swift`.

import Foundation

/// Sendable facade over thread-safe UserDefaults, hence `@unchecked`; callers
/// must still serialize compound read-modify-write mutations. iOS requires the
/// App Group (except unsigned tests), while macOS may use `.standard`. API keys
/// are resolved from Keychain and never saved here.
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
        //
        // Exception: unsigned XCTest hosts (`CODE_SIGNING_ALLOWED=NO`) often
        // lack the App Group container. `fatalError` here aborts the whole
        // test process (SIGTRAP) and masks real assertion failures — use an
        // isolated suite only while XCTest is loaded.
        #if DEBUG
        if NSClassFromString("XCTestCase") != nil {
            let suiteName = "\(AppGroup.identifier).xctest-fallback"
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
            return
        }
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
        let baseline = AppGroupConfiguration.load(fromAvailable: defaults)
        var config = baseline
        transform(&config)
        config.saveChanges(since: baseline, to: defaults)
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
    public var credentialSource: CredentialSource { configuration.credentialSource }
    /// Non-secret host-authentication marker used to gate account-funded grants.
    public var isManagedGatewayAccountSessionAvailable: Bool {
        defaults.bool(
            forKey: AppGroupConfiguration.Keys.managedGatewayAccountSessionAvailable
        )
    }
    public var uiLanguage: AppUILanguage { configuration.uiLanguage }
    public var translationEnabled: Bool { configuration.translationEnabled }
    public var translationTargetLocaleId: String { configuration.translationTargetLocaleId }
    public var handednessPreference: HandednessPreference { configuration.handednessPreference }
    public var cursorDragNavigationEnabled: Bool { configuration.cursorDragNavigationEnabled }
    public var keyboardHapticIntensity: KeyboardHapticIntensity { configuration.keyboardHapticIntensity }
    public var polishIntensity: PolishIntensity { configuration.polishIntensity }
    public var aiResponseLength: AIResponseLength { configuration.aiResponseLength }
    public var polishStyleCatalog: PolishStyleCatalog { configuration.polishStyleCatalog }
    public var activePolishStyleId: String { configuration.activePolishStyleId }
    public var activePolishStyle: PolishStylePack {
        PolishStylePackCatalog.resolve(id: activePolishStyleId, userCatalog: polishStyleCatalog)
    }
    public var llmThinkingEnabled: Bool { configuration.llmThinkingEnabled }
    public var clipboardHistoryEnabled: Bool { configuration.clipboardHistoryEnabled }
    public var clipboardCandidateBarEnabled: Bool { configuration.clipboardCandidateBarEnabled }
    public var isPolishKeyMissing: Bool { configuration.isPolishKeyMissing }
    public var isTranslationEffective: Bool { configuration.isTranslationEffective }
    public var isLocalEngine: Bool { configuration.isLocalEngine }
    public var polishModeForPipeline: PolishingService.PolishMode { configuration.polishModeForPipeline }
    public var polishProviderIdOverride: String? { configuration.polishProviderIdOverride }
    public var isCloudAPIKeyMissingForVoiceInput: Bool { configuration.isCloudAPIKeyMissingForVoiceInput }
    public var localASRCustomLanguageModelEnabled: Bool { configuration.localASRCustomLanguageModelEnabled }
    /// Kept off `AppGroupConfiguration.save()` so other settings writes cannot clobber it.
    public var agentSkillLayout: AIAgentSkillLayout {
        Self.decodeAgentSkillLayout(
            from: defaults,
            userCatalog: agentUserSkillCatalog,
            officialCatalog: officialSkillCatalog,
            uiLanguage: uiLanguage
        )
    }

    public var agentUserSkillCatalog: AIUserSkillCatalog {
        Self.decodeUserSkillCatalog(from: defaults)
    }

    /// Last-known-good host-fetched catalog. The extension only reads this snapshot.
    public var officialSkillCatalog: OfficialSkillCatalog {
        Self.decodeOfficialSkillCatalog(from: defaults)
    }

    public var resolvedAgentSkillCatalog: [AIClipboardSkill] {
        AIClipboardSkillCatalog.all(
            officialCatalog: officialSkillCatalog,
            userCatalog: agentUserSkillCatalog,
            uiLanguage: uiLanguage
        )
    }

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

    public func setCredentialSource(_ source: CredentialSource) {
        mutateConfiguration { $0.credentialSource = source }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setManagedGatewayAccountSessionAvailable(_ available: Bool) {
        defaults.set(
            available,
            forKey: AppGroupConfiguration.Keys.managedGatewayAccountSessionAvailable
        )
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

    public func setKeyboardHapticIntensity(_ intensity: KeyboardHapticIntensity) {
        mutateConfiguration { $0.keyboardHapticIntensity = intensity }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setPolishIntensity(_ intensity: PolishIntensity) {
        mutateConfiguration { $0.polishIntensity = intensity }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setAIResponseLength(_ length: AIResponseLength) {
        mutateConfiguration { $0.aiResponseLength = length }
        AppGroupConfigDarwin.postConfigChanged()
    }

    // MARK: - Polish styles

    public func setPolishStyleCatalog(_ catalog: PolishStyleCatalog) {
        mutateConfiguration { $0.polishStyleCatalog = catalog }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setActivePolishStyleId(_ id: String) {
        mutateConfiguration { config in
            config.activePolishStyleId = PolishStylePackCatalog.isValidActiveID(
                id,
                userCatalog: config.polishStyleCatalog
            ) ? id : PolishStylePackCatalog.defaultID
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func deletePolishStylePack(id: String, at date: Date = Date()) {
        mutateConfiguration { config in
            config.polishStyleCatalog.recordDeletion(of: id, at: date)
            if config.activePolishStyleId == id {
                config.activePolishStyleId = PolishStylePackCatalog.defaultID
            }
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setLLMThinkingEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.llmThinkingEnabled = enabled }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setClipboardHistoryEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.clipboardHistoryEnabled = enabled }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setClipboardCandidateBarEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.clipboardCandidateBarEnabled = enabled }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setLocalASRCustomLanguageModelEnabled(_ enabled: Bool) {
        mutateConfiguration { $0.localASRCustomLanguageModelEnabled = enabled }
    }

    public func setAgentSkillLayout(_ layout: AIAgentSkillLayout) {
        do {
            let data = try JSONEncoder().encode(
                layout.sanitized(catalog: resolvedAgentSkillCatalog)
            )
            defaults.set(data, forKey: AppGroupConfiguration.Keys.agentSkillLayout)
            defaults.set(
                Self.currentAgentSkillDefaultsMigrationVersion,
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            )
        } catch {
            OSGLog.config.warning("agentSkillLayout encode failed: \(error.localizedDescription, privacy: .public)")
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    /// Stores one encoded value so readers observe either the old or new
    /// complete snapshot, never partially updated catalog metadata.
    public func setOfficialSkillCatalog(_ catalog: OfficialSkillCatalog) throws {
        let validated = try catalog.validated()
        let data = try JSONEncoder().encode(validated)
        defaults.set(data, forKey: AppGroupConfiguration.Keys.officialSkillCatalog)
        defaults.synchronize()
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setAgentUserSkillCatalog(_ catalog: AIUserSkillCatalog) {
        do {
            defaults.set(
                try JSONEncoder().encode(catalog),
                forKey: AppGroupConfiguration.Keys.agentUserSkillCatalog
            )
        } catch {
            OSGLog.config.warning(
                "agentUserSkillCatalog encode failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        AppGroupConfigDarwin.postConfigChanged()
    }

    public func setPendingShortcutRun(skillID: String, titles: [String]) {
        let payload = AIAgentShortcutRunPayload(skillID: skillID, titles: titles)
        if let data = AIAgentShortcutRun.encode(payload) {
            defaults.set(data, forKey: AIAgentShortcutRun.pendingKey)
            AIAgentShortcutRun.trace(
                "appGroup.writePending skill=\(skillID) items=\(titles.count) bytes=\(data.count)"
            )
        } else {
            AIAgentShortcutRun.trace("appGroup.writePending FAILED encode skill=\(skillID)")
        }
    }

    public func consumePendingShortcutRun(now: Date = Date()) -> AIAgentShortcutRunPayload? {
        let data = defaults.data(forKey: AIAgentShortcutRun.pendingKey)
        defaults.removeObject(forKey: AIAgentShortcutRun.pendingKey)
        guard let data else {
            AIAgentShortcutRun.trace("appGroup.consumePending missing")
            return nil
        }
        guard let payload = AIAgentShortcutRun.decode(data, now: now) else {
            AIAgentShortcutRun.trace(
                "appGroup.consumePending dropped bytes=\(data.count) (expired or empty titles)"
            )
            return nil
        }
        AIAgentShortcutRun.trace(
            "appGroup.consumePending ok skill=\(payload.skillID) items=\(payload.titles.count)"
        )
        return payload
    }

    private static func decodeAgentSkillLayout(
        from defaults: UserDefaults,
        userCatalog: AIUserSkillCatalog,
        officialCatalog: OfficialSkillCatalog,
        uiLanguage: AppUILanguage
    ) -> AIAgentSkillLayout {
        let catalog = AIClipboardSkillCatalog.all(
            officialCatalog: officialCatalog,
            userCatalog: userCatalog,
            uiLanguage: uiLanguage
        )
        guard let data = defaults.data(forKey: AppGroupConfiguration.Keys.agentSkillLayout) else {
            defaults.set(
                currentAgentSkillDefaultsMigrationVersion,
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            )
            return .default
        }
        do {
            let decoded = try JSONDecoder().decode(AIAgentSkillLayout.self, from: data)
                .sanitized(catalog: catalog)
            guard defaults.integer(
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            ) < currentAgentSkillDefaultsMigrationVersion else {
                return decoded
            }

            // Preserve any legacy default the user explicitly turned off.
            // Export skills and semantic skills were not previously defaults,
            // so append them once without disturbing the user's saved order.
            let legacyDefaults = Set([
                AIClipboardSkillCatalog.replyID,
                AIClipboardSkillCatalog.summarizeID,
                AIClipboardSkillCatalog.translateID
            ])
            let additions = AIAgentSkillLayout.defaultEnabledIDs.filter {
                !legacyDefaults.contains($0) && !decoded.enabledIDs.contains($0)
            }
            let migrated = AIAgentSkillLayout(
                enabledIDs: decoded.enabledIDs + additions,
                confirmedShortcutIDs: decoded.confirmedShortcutIDs
            ).sanitized(catalog: catalog)
            if let migratedData = try? JSONEncoder().encode(migrated) {
                defaults.set(migratedData, forKey: AppGroupConfiguration.Keys.agentSkillLayout)
            }
            defaults.set(
                currentAgentSkillDefaultsMigrationVersion,
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            )
            return migrated
        } catch {
            OSGLog.config.warning("agentSkillLayout decode failed: \(error.localizedDescription, privacy: .public)")
            defaults.set(
                currentAgentSkillDefaultsMigrationVersion,
                forKey: AppGroupConfiguration.Keys.agentSkillDefaultsMigrationVersion
            )
            return .default
        }
    }

    private static let currentAgentSkillDefaultsMigrationVersion = 1

    private static func decodeUserSkillCatalog(from defaults: UserDefaults) -> AIUserSkillCatalog {
        guard let data = defaults.data(forKey: AppGroupConfiguration.Keys.agentUserSkillCatalog) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(AIUserSkillCatalog.self, from: data)
        } catch {
            OSGLog.config.warning(
                "agentUserSkillCatalog decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return .empty
        }
    }

    private static func decodeOfficialSkillCatalog(from defaults: UserDefaults) -> OfficialSkillCatalog {
        guard let data = defaults.data(forKey: AppGroupConfiguration.Keys.officialSkillCatalog) else {
            return .empty
        }
        do {
            return try JSONDecoder().decode(OfficialSkillCatalog.self, from: data).validated()
        } catch {
            OSGLog.config.warning(
                "officialSkillCatalog decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return .empty
        }
    }

    public var hasCompletedOnboarding: Bool {
        get { configuration.hasCompletedOnboarding }
        set { setHasCompletedOnboarding(newValue) }
    }

    public var onboardingPage: Int {
        get { configuration.onboardingPage }
        set { setOnboardingPage(newValue) }
    }

    /// Commits onboarding to both the App Group and the reboot-durable
    /// Keychain marker; callers must preserve this dual-write invariant.
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
        #if os(iOS)
        // Host redeploys Rime sidecar; extension picks it up next typing open.
        PersonalDictionaryRimeSync.scheduleAfterDictionaryChange()
        #endif
    }

    public func deletePersonalDictionaryEntry(id: UUID, at date: Date = Date()) {
        mutateConfiguration { config in
            config.personalDictionary.entries.removeAll { $0.id == id }
            config.personalDictionary.deletedEntryIDs[id] = date
        }
        AppGroupConfigDarwin.postConfigChanged()
        #if os(iOS)
        PersonalDictionaryRimeSync.scheduleAfterDictionaryChange()
        #endif
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

    public func makeClient(
        taskKind: ManagedGatewayTaskKind?,
        requestPurpose: ManagedGatewayRequestPurpose?,
        oobeFeature: ManagedGatewayOOBEFeature?
    ) -> LLMClient {
        configuration.makeClient(
            taskKind: taskKind,
            requestPurpose: requestPurpose,
            oobeFeature: oobeFeature
        )
    }
}
