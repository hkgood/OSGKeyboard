// SyncedAppSettingsV2.swift
// OSGKeyboard · Shared
//
// Versioned settings payload with per-field merge metadata. API keys are
// intentionally excluded — they sync through iCloud Keychain.

import Foundation

public struct SyncedAppSettingsV2: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let kvsKey = "appSettings.v2"

    public var schemaVersion: Int
    public var providerId: SyncedField<String>
    public var baseURL: SyncedField<String>
    public var model: SyncedField<String>
    /// Cloud ASR provider — independent from polish `providerId`.
    public var asrProviderId: SyncedField<String>
    public var asrBaseURL: SyncedField<String>
    public var asrModel: SyncedField<String>
    public var modeId: SyncedField<String>
    public var localeId: SyncedField<String>
    public var engineMode: SyncedField<String>
    public var hasAcknowledgedCloudSharing: SyncedField<Bool>
    public var uiLanguage: SyncedField<AppUILanguage>
    public var translationTargetLocaleId: SyncedField<String>
    public var handednessPreference: SyncedField<HandednessPreference>
    public var cursorDragNavigationEnabled: SyncedField<Bool>
    public var polishIntensity: SyncedField<PolishIntensity>
    public var llmThinkingEnabled: SyncedField<Bool>
    public var flowSkipAppSwitch: SyncedField<Bool>
    public var flowInactivityDuration: SyncedField<FlowInactivityDuration>

    public init(
        schemaVersion: Int = Self.schemaVersion,
        providerId: SyncedField<String>,
        baseURL: SyncedField<String>,
        model: SyncedField<String>,
        asrProviderId: SyncedField<String>,
        asrBaseURL: SyncedField<String>,
        asrModel: SyncedField<String>,
        modeId: SyncedField<String>,
        localeId: SyncedField<String>,
        engineMode: SyncedField<String>,
        hasAcknowledgedCloudSharing: SyncedField<Bool>,
        uiLanguage: SyncedField<AppUILanguage>,
        translationTargetLocaleId: SyncedField<String>,
        handednessPreference: SyncedField<HandednessPreference>,
        cursorDragNavigationEnabled: SyncedField<Bool>,
        polishIntensity: SyncedField<PolishIntensity>,
        llmThinkingEnabled: SyncedField<Bool>,
        flowSkipAppSwitch: SyncedField<Bool>,
        flowInactivityDuration: SyncedField<FlowInactivityDuration>
    ) {
        self.schemaVersion = schemaVersion
        self.providerId = providerId
        self.baseURL = baseURL
        self.model = model
        self.asrProviderId = asrProviderId
        self.asrBaseURL = asrBaseURL
        self.asrModel = asrModel
        self.modeId = modeId
        self.localeId = localeId
        self.engineMode = engineMode
        self.hasAcknowledgedCloudSharing = hasAcknowledgedCloudSharing
        self.uiLanguage = uiLanguage
        self.translationTargetLocaleId = translationTargetLocaleId
        self.handednessPreference = handednessPreference
        self.cursorDragNavigationEnabled = cursorDragNavigationEnabled
        self.polishIntensity = polishIntensity
        self.llmThinkingEnabled = llmThinkingEnabled
        self.flowSkipAppSwitch = flowSkipAppSwitch
        self.flowInactivityDuration = flowInactivityDuration
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case providerId
        case baseURL
        case model
        case asrProviderId
        case asrBaseURL
        case asrModel
        case modeId
        case localeId
        case engineMode
        case hasAcknowledgedCloudSharing
        case uiLanguage
        case translationTargetLocaleId
        case handednessPreference
        case cursorDragNavigationEnabled
        case polishIntensity
        case llmThinkingEnabled
        case flowSkipAppSwitch
        case flowInactivityDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        providerId = try container.decode(SyncedField<String>.self, forKey: .providerId)
        baseURL = try container.decode(SyncedField<String>.self, forKey: .baseURL)
        model = try container.decode(SyncedField<String>.self, forKey: .model)
        modeId = try container.decode(SyncedField<String>.self, forKey: .modeId)
        localeId = try container.decode(SyncedField<String>.self, forKey: .localeId)
        engineMode = try container.decode(SyncedField<String>.self, forKey: .engineMode)
        hasAcknowledgedCloudSharing = try container.decode(SyncedField<Bool>.self, forKey: .hasAcknowledgedCloudSharing)
        uiLanguage = try container.decode(SyncedField<AppUILanguage>.self, forKey: .uiLanguage)
        translationTargetLocaleId = try container.decode(
            SyncedField<String>.self,
            forKey: .translationTargetLocaleId
        )
        handednessPreference = try container.decode(
            SyncedField<HandednessPreference>.self,
            forKey: .handednessPreference
        )
        cursorDragNavigationEnabled = try container.decode(
            SyncedField<Bool>.self,
            forKey: .cursorDragNavigationEnabled
        )
        polishIntensity = try container.decode(SyncedField<PolishIntensity>.self, forKey: .polishIntensity)
        llmThinkingEnabled = try container.decodeIfPresent(
            SyncedField<Bool>.self,
            forKey: .llmThinkingEnabled
        ) ?? SyncedField(value: false, updatedAt: polishIntensity.updatedAt, deviceID: polishIntensity.deviceID)
        flowSkipAppSwitch = try container.decode(SyncedField<Bool>.self, forKey: .flowSkipAppSwitch)
        flowInactivityDuration = try container.decode(
            SyncedField<FlowInactivityDuration>.self,
            forKey: .flowInactivityDuration
        )

        if let asrProvider = try container.decodeIfPresent(SyncedField<String>.self, forKey: .asrProviderId) {
            asrProviderId = asrProvider
        } else {
            asrProviderId = providerId
        }
        if let asrURL = try container.decodeIfPresent(SyncedField<String>.self, forKey: .asrBaseURL) {
            asrBaseURL = asrURL
        } else {
            asrBaseURL = baseURL
        }
        if let asrModelField = try container.decodeIfPresent(SyncedField<String>.self, forKey: .asrModel) {
            asrModel = asrModelField
        } else {
            let fallbackModel = CloudASRModelCatalog.defaultModel(for: providerId.value)
            asrModel = SyncedField(
                value: fallbackModel,
                updatedAt: model.updatedAt,
                deviceID: model.deviceID
            )
        }
    }

    /// Monotonic stamp used for `settingsCloudUpdatedAt` bookkeeping.
    public var latestUpdatedAt: Date {
        [
            providerId.updatedAt,
            baseURL.updatedAt,
            model.updatedAt,
            asrProviderId.updatedAt,
            asrBaseURL.updatedAt,
            asrModel.updatedAt,
            modeId.updatedAt,
            localeId.updatedAt,
            engineMode.updatedAt,
            hasAcknowledgedCloudSharing.updatedAt,
            uiLanguage.updatedAt,
            translationTargetLocaleId.updatedAt,
            handednessPreference.updatedAt,
            cursorDragNavigationEnabled.updatedAt,
            polishIntensity.updatedAt,
            llmThinkingEnabled.updatedAt,
            flowSkipAppSwitch.updatedAt,
            flowInactivityDuration.updatedAt,
        ].max() ?? .distantPast
    }
}

public extension SyncedAppSettingsV2 {
    static func from(configuration: AppGroupConfiguration, deviceID: String) -> SyncedAppSettingsV2 {
        seeded(from: configuration, deviceID: deviceID, updatedAt: Date())
    }

    /// Build a payload from configuration using one shared timestamp (for merge bookkeeping).
    static func seeded(
        from configuration: AppGroupConfiguration,
        deviceID: String,
        updatedAt: Date
    ) -> SyncedAppSettingsV2 {
        func field<T>(_ value: T) -> SyncedField<T> {
            SyncedField(value: value, updatedAt: updatedAt, deviceID: deviceID)
        }
        return SyncedAppSettingsV2(
            providerId: field(configuration.providerId),
            baseURL: field(configuration.baseURL),
            model: field(configuration.model),
            asrProviderId: field(configuration.asrProviderId),
            asrBaseURL: field(configuration.asrBaseURL),
            asrModel: field(configuration.asrModel),
            modeId: field(configuration.modeId),
            localeId: field(configuration.localeId),
            engineMode: field(configuration.engineMode),
            hasAcknowledgedCloudSharing: field(configuration.hasAcknowledgedCloudSharing),
            uiLanguage: field(configuration.uiLanguage),
            translationTargetLocaleId: field(configuration.translationTargetLocaleId),
            handednessPreference: field(configuration.handednessPreference),
            cursorDragNavigationEnabled: field(configuration.cursorDragNavigationEnabled),
            polishIntensity: field(configuration.polishIntensity),
            llmThinkingEnabled: field(configuration.llmThinkingEnabled),
            flowSkipAppSwitch: field(configuration.flowSkipAppSwitch),
            flowInactivityDuration: field(configuration.flowInactivityDuration)
        )
    }

    /// Upgrade a legacy v1 blob into per-field metadata on this device.
    static func migrated(from legacy: SyncedAppSettings, deviceID: String) -> SyncedAppSettingsV2 {
        let stamp = legacy.updatedAt
        func field<T>(_ value: T) -> SyncedField<T> {
            SyncedField(value: value, updatedAt: stamp, deviceID: deviceID)
        }
        let provider = field(legacy.providerId)
        return SyncedAppSettingsV2(
            providerId: provider,
            baseURL: field(legacy.baseURL),
            model: field(legacy.model),
            asrProviderId: provider,
            asrBaseURL: field(legacy.baseURL),
            asrModel: field(CloudASRModelCatalog.defaultModel(for: legacy.providerId)),
            modeId: field(legacy.modeId),
            localeId: field(legacy.localeId),
            engineMode: field(legacy.engineMode),
            hasAcknowledgedCloudSharing: field(legacy.hasAcknowledgedCloudSharing),
            uiLanguage: field(legacy.uiLanguage),
            translationTargetLocaleId: field(legacy.translationTargetLocaleId),
            handednessPreference: field(legacy.handednessPreference),
            cursorDragNavigationEnabled: field(legacy.cursorDragNavigationEnabled),
            polishIntensity: field(legacy.polishIntensity),
            llmThinkingEnabled: field(false),
            flowSkipAppSwitch: field(legacy.flowSkipAppSwitch),
            flowInactivityDuration: field(legacy.flowInactivityDuration)
        )
    }

    static func merge(local: SyncedAppSettingsV2, remote: SyncedAppSettingsV2) -> SyncedAppSettingsV2 {
        SyncedAppSettingsV2(
            providerId: .merge(local: local.providerId, remote: remote.providerId),
            baseURL: .merge(local: local.baseURL, remote: remote.baseURL),
            model: .merge(local: local.model, remote: remote.model),
            asrProviderId: .merge(local: local.asrProviderId, remote: remote.asrProviderId),
            asrBaseURL: .merge(local: local.asrBaseURL, remote: remote.asrBaseURL),
            asrModel: .merge(local: local.asrModel, remote: remote.asrModel),
            modeId: .merge(local: local.modeId, remote: remote.modeId),
            localeId: .merge(local: local.localeId, remote: remote.localeId),
            engineMode: .merge(local: local.engineMode, remote: remote.engineMode),
            hasAcknowledgedCloudSharing: .merge(
                local: local.hasAcknowledgedCloudSharing,
                remote: remote.hasAcknowledgedCloudSharing
            ),
            uiLanguage: .merge(local: local.uiLanguage, remote: remote.uiLanguage),
            translationTargetLocaleId: .merge(
                local: local.translationTargetLocaleId,
                remote: remote.translationTargetLocaleId
            ),
            handednessPreference: .merge(local: local.handednessPreference, remote: remote.handednessPreference),
            cursorDragNavigationEnabled: .merge(
                local: local.cursorDragNavigationEnabled,
                remote: remote.cursorDragNavigationEnabled
            ),
            polishIntensity: .merge(local: local.polishIntensity, remote: remote.polishIntensity),
            llmThinkingEnabled: .merge(local: local.llmThinkingEnabled, remote: remote.llmThinkingEnabled),
            flowSkipAppSwitch: .merge(local: local.flowSkipAppSwitch, remote: remote.flowSkipAppSwitch),
            flowInactivityDuration: .merge(
                local: local.flowInactivityDuration,
                remote: remote.flowInactivityDuration
            )
        )
    }

    func applying(to configuration: inout AppGroupConfiguration) {
        configuration.providerId = providerId.value
        configuration.baseURL = baseURL.value
        configuration.model = model.value
        configuration.asrProviderId = asrProviderId.value
        configuration.asrBaseURL = asrBaseURL.value
        configuration.asrModel = asrModel.value
        configuration.modeId = modeId.value
        configuration.localeId = localeId.value
        configuration.engineMode = engineMode.value
        configuration.hasAcknowledgedCloudSharing = hasAcknowledgedCloudSharing.value
        configuration.uiLanguage = uiLanguage.value
        configuration.translationTargetLocaleId = translationTargetLocaleId.value
        configuration.handednessPreference = handednessPreference.value
        configuration.cursorDragNavigationEnabled = cursorDragNavigationEnabled.value
        configuration.polishIntensity = polishIntensity.value
        configuration.llmThinkingEnabled = llmThinkingEnabled.value
        configuration.flowSkipAppSwitch = flowSkipAppSwitch.value
        configuration.flowInactivityDuration = flowInactivityDuration.value
    }

    /// Stamp fields whose values differ from `configuration` with this device id.
    func patchLocalChanges(from configuration: AppGroupConfiguration, deviceID: String) -> SyncedAppSettingsV2 {
        var copy = self
        func patch<T: Equatable>(_ field: inout SyncedField<T>, value: T) {
            guard field.value != value else { return }
            field = .make(value: value, deviceID: deviceID)
        }
        patch(&copy.providerId, value: configuration.providerId)
        patch(&copy.baseURL, value: configuration.baseURL)
        patch(&copy.model, value: configuration.model)
        patch(&copy.asrProviderId, value: configuration.asrProviderId)
        patch(&copy.asrBaseURL, value: configuration.asrBaseURL)
        patch(&copy.asrModel, value: configuration.asrModel)
        patch(&copy.modeId, value: configuration.modeId)
        patch(&copy.localeId, value: configuration.localeId)
        patch(&copy.engineMode, value: configuration.engineMode)
        patch(&copy.hasAcknowledgedCloudSharing, value: configuration.hasAcknowledgedCloudSharing)
        patch(&copy.uiLanguage, value: configuration.uiLanguage)
        patch(&copy.translationTargetLocaleId, value: configuration.translationTargetLocaleId)
        patch(&copy.handednessPreference, value: configuration.handednessPreference)
        patch(&copy.cursorDragNavigationEnabled, value: configuration.cursorDragNavigationEnabled)
        patch(&copy.polishIntensity, value: configuration.polishIntensity)
        patch(&copy.llmThinkingEnabled, value: configuration.llmThinkingEnabled)
        patch(&copy.flowSkipAppSwitch, value: configuration.flowSkipAppSwitch)
        patch(&copy.flowInactivityDuration, value: configuration.flowInactivityDuration)
        return copy
    }

    /// Refresh only fields owned by `deviceID` from the current local configuration.
    func refreshedLocalFields(from configuration: AppGroupConfiguration, deviceID: String) -> SyncedAppSettingsV2 {
        var copy = self
        let now = Date()
        func touch<T>(_ field: inout SyncedField<T>, value: T) {
            guard field.deviceID == deviceID else { return }
            field.value = value
            field.updatedAt = now
        }
        touch(&copy.providerId, value: configuration.providerId)
        touch(&copy.baseURL, value: configuration.baseURL)
        touch(&copy.model, value: configuration.model)
        touch(&copy.asrProviderId, value: configuration.asrProviderId)
        touch(&copy.asrBaseURL, value: configuration.asrBaseURL)
        touch(&copy.asrModel, value: configuration.asrModel)
        touch(&copy.modeId, value: configuration.modeId)
        touch(&copy.localeId, value: configuration.localeId)
        touch(&copy.engineMode, value: configuration.engineMode)
        touch(&copy.hasAcknowledgedCloudSharing, value: configuration.hasAcknowledgedCloudSharing)
        touch(&copy.uiLanguage, value: configuration.uiLanguage)
        touch(&copy.translationTargetLocaleId, value: configuration.translationTargetLocaleId)
        touch(&copy.handednessPreference, value: configuration.handednessPreference)
        touch(&copy.cursorDragNavigationEnabled, value: configuration.cursorDragNavigationEnabled)
        touch(&copy.polishIntensity, value: configuration.polishIntensity)
        touch(&copy.llmThinkingEnabled, value: configuration.llmThinkingEnabled)
        touch(&copy.flowSkipAppSwitch, value: configuration.flowSkipAppSwitch)
        touch(&copy.flowInactivityDuration, value: configuration.flowInactivityDuration)
        return copy
    }
}
