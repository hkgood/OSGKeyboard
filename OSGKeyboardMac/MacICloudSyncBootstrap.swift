// MacICloudSyncBootstrap.swift
// OSGKeyboard · Mac
//
// Wires the shared iCloud KVS sync layer to macOS UserDefaults so settings
// and personal dictionary stay aligned with the iOS app.

import Foundation

@MainActor
enum MacICloudSyncBootstrap {
    private static var configured = false
    private static var cloudSync: AppCloudSync?

    static func configure(defaults: UserDefaults) {
        guard !configured else { return }
        configured = true
        let makeStore = { AppGroupStore(defaults: defaults) }
        cloudSync = AppCloudSync(makeStore: makeStore, historyDefaults: { defaults })
        cloudSync?.startObservingExternalChanges()
    }

    static func pullIfEnabled() async {
        await cloudSync?.pullAllIfEnabled()
    }

    static var settingsSync: SettingsCloudSync {
        if let cloudSync {
            return cloudSync.settingsSyncService
        }
        return SettingsCloudSync(makeStore: { AppGroupStore(defaults: .standard) })
    }

    static var dictionarySync: PersonalDictionaryCloudSync {
        cloudSync?.dictionarySyncService ?? PersonalDictionaryCloudSync(makeStore: { AppGroupStore(defaults: .standard) })
    }

    static var appCloudSync: AppCloudSync {
        cloudSync ?? AppCloudSync.shared
    }
}
