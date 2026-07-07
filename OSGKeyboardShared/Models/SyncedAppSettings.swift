// SyncedAppSettings.swift
// OSGKeyboard · Shared
//
// User-facing app settings mirrored through iCloud KVS. Excludes
// device-local state (onboarding progress, detected app context,
// personal dictionary blob, and API keys in Keychain).

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
        flowInactivityDuration: FlowInactivityDuration
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
    }
}

public extension SyncedAppSettings {
    /// Build a cloud payload from the current App Group configuration.
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

    /// Apply syncable fields onto a configuration, preserving device-local
    /// fields such as onboarding progress and the personal dictionary.
    func applying(to configuration: inout AppGroupConfiguration) {
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

    /// Last-write-wins merge for whole settings blobs.
    static func merge(local: SyncedAppSettings, remote: SyncedAppSettings) -> SyncedAppSettings {
        remote.updatedAt >= local.updatedAt ? remote : local
    }
}
