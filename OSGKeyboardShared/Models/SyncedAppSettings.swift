// SyncedAppSettings.swift
// OSGKeyboard · Shared
//
// Legacy v1 settings blob (read-only migration input). New sync uses
// `SyncedAppSettingsV2`. API keys never belong in KVS payloads.

import Foundation

public struct SyncedAppSettings: Codable, Sendable, Equatable {
    public var updatedAt: Date
    public var providerId: String
    public var baseURL: String
    public var model: String
    public var modeId: String
    public var localeId: String
    public var engineMode: String
    public var hasAcknowledgedCloudSharing: Bool
    public var uiLanguage: AppUILanguage
    public var translationTargetLocaleId: String
    public var handednessPreference: HandednessPreference
    public var cursorDragNavigationEnabled: Bool
    public var polishIntensity: PolishIntensity
    public var flowSkipAppSwitch: Bool
    public var flowInactivityDuration: FlowInactivityDuration
    /// Deprecated — decoded for backward compatibility only; never applied.
    public var providerAPIKeys: [String: String]

    public init(
        updatedAt: Date = Date(),
        providerId: String,
        baseURL: String,
        model: String,
        modeId: String,
        localeId: String,
        engineMode: String,
        hasAcknowledgedCloudSharing: Bool,
        uiLanguage: AppUILanguage,
        translationTargetLocaleId: String,
        handednessPreference: HandednessPreference,
        cursorDragNavigationEnabled: Bool,
        polishIntensity: PolishIntensity,
        flowSkipAppSwitch: Bool,
        flowInactivityDuration: FlowInactivityDuration,
        providerAPIKeys: [String: String] = [:]
    ) {
        self.updatedAt = updatedAt
        self.providerId = providerId
        self.baseURL = baseURL
        self.model = model
        self.modeId = modeId
        self.localeId = localeId
        self.engineMode = engineMode
        self.hasAcknowledgedCloudSharing = hasAcknowledgedCloudSharing
        self.uiLanguage = uiLanguage
        self.translationTargetLocaleId = translationTargetLocaleId
        self.handednessPreference = handednessPreference
        self.cursorDragNavigationEnabled = cursorDragNavigationEnabled
        self.polishIntensity = polishIntensity
        self.flowSkipAppSwitch = flowSkipAppSwitch
        self.flowInactivityDuration = flowInactivityDuration
        self.providerAPIKeys = providerAPIKeys
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        providerId = try container.decode(String.self, forKey: .providerId)
        baseURL = try container.decode(String.self, forKey: .baseURL)
        model = try container.decode(String.self, forKey: .model)
        modeId = try container.decode(String.self, forKey: .modeId)
        localeId = try container.decode(String.self, forKey: .localeId)
        engineMode = try container.decode(String.self, forKey: .engineMode)
        hasAcknowledgedCloudSharing = try container.decode(Bool.self, forKey: .hasAcknowledgedCloudSharing)
        uiLanguage = try container.decode(AppUILanguage.self, forKey: .uiLanguage)
        translationTargetLocaleId = try container.decode(String.self, forKey: .translationTargetLocaleId)
        handednessPreference = try container.decode(HandednessPreference.self, forKey: .handednessPreference)
        cursorDragNavigationEnabled = try container.decode(Bool.self, forKey: .cursorDragNavigationEnabled)
        polishIntensity = try container.decode(PolishIntensity.self, forKey: .polishIntensity)
        flowSkipAppSwitch = try container.decode(Bool.self, forKey: .flowSkipAppSwitch)
        flowInactivityDuration = try container.decode(FlowInactivityDuration.self, forKey: .flowInactivityDuration)
        providerAPIKeys = try container.decodeIfPresent([String: String].self, forKey: .providerAPIKeys) ?? [:]
    }

    /// Apply legacy scalar fields only — never touches Keychain.
    func applyingScalars(to configuration: inout AppGroupConfiguration) {
        configuration.providerId = providerId
        configuration.baseURL = baseURL
        configuration.model = model
        configuration.modeId = modeId
        configuration.localeId = localeId
        configuration.engineMode = engineMode
        configuration.hasAcknowledgedCloudSharing = hasAcknowledgedCloudSharing
        configuration.uiLanguage = uiLanguage
        configuration.translationTargetLocaleId = translationTargetLocaleId
        configuration.handednessPreference = handednessPreference
        configuration.cursorDragNavigationEnabled = cursorDragNavigationEnabled
        configuration.polishIntensity = polishIntensity
        configuration.flowSkipAppSwitch = flowSkipAppSwitch
        configuration.flowInactivityDuration = flowInactivityDuration
    }
}

public extension SyncedAppSettings {
    static let legacyKVSKey = "appSettings.v1"

    static func from(configuration: AppGroupConfiguration, updatedAt: Date = Date()) -> SyncedAppSettings {
        SyncedAppSettings(
            updatedAt: updatedAt,
            providerId: configuration.providerId,
            baseURL: configuration.baseURL,
            model: configuration.model,
            modeId: configuration.modeId,
            localeId: configuration.localeId,
            engineMode: configuration.engineMode,
            hasAcknowledgedCloudSharing: configuration.hasAcknowledgedCloudSharing,
            uiLanguage: configuration.uiLanguage,
            translationTargetLocaleId: configuration.translationTargetLocaleId,
            handednessPreference: configuration.handednessPreference,
            cursorDragNavigationEnabled: configuration.cursorDragNavigationEnabled,
            polishIntensity: configuration.polishIntensity,
            flowSkipAppSwitch: configuration.flowSkipAppSwitch,
            flowInactivityDuration: configuration.flowInactivityDuration
        )
    }
}
