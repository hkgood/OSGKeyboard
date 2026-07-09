// MacICloudSyncRows.swift
// OSGKeyboard · Mac
//
// iCloud sync toggles for settings and personal dictionary — same KVS
// keys and merge rules as the iOS settings page. Rendered as native Form
// rows (Toggle + optional action / error) so they sit inside a grouped
// `Form` section and match System Settings exactly.

import SwiftUI

struct MacSettingsICloudSyncRow: View {
    let defaults: UserDefaults
    let language: AppUILanguage

    @Environment(\.themePalette) private var palette
    @State private var isEnabled = false
    @State private var syncErrorMessage: String?
    @State private var isApplyingToggle = false
    @State private var isSyncingNow = false

    var body: some View {
        Toggle(isOn: toggleBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MacL10n.string("mac.sync.settingsTitle", language: language))
                Text(MacL10n.string("mac.sync.settingsSubtitle", language: language))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(palette.accent)
        .disabled(isApplyingToggle)
        .onAppear { reloadFromStore() }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            reloadFromStore()
        }

        if isEnabled {
            Button {
                syncNow()
            } label: {
                HStack(spacing: Spacing.xs) {
                    if isSyncingNow { ProgressView().controlSize(.small) }
                    Text(MacL10n.string("mac.sync.syncNow", language: language))
                }
            }
            .disabled(isSyncingNow || isApplyingToggle)
        }

        if let syncErrorMessage {
            Text(syncErrorMessage)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.danger)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard newValue != isEnabled else { return }
                newValue ? enableSync() : disableSync()
            }
        )
    }

    private func reloadFromStore() {
        isEnabled = AppGroupStore(defaults: defaults).settingsICloudSyncEnabled
    }

    private func enableSync() {
        isApplyingToggle = true
        syncErrorMessage = nil
        Task {
            do {
                try await MacICloudSyncBootstrap.settingsSync.enableSync()
                reloadFromStore()
            } catch {
                isEnabled = false
                syncErrorMessage = MacL10n.string("mac.sync.error.generic", language: language)
            }
            isApplyingToggle = false
        }
    }

    private func disableSync() {
        MacICloudSyncBootstrap.settingsSync.disableSync()
        isEnabled = false
        syncErrorMessage = nil
    }

    private func syncNow() {
        isSyncingNow = true
        syncErrorMessage = nil
        Task {
            do {
                try await MacICloudSyncBootstrap.appCloudSync.syncNow()
            } catch {
                syncErrorMessage = MacL10n.string("mac.sync.error.generic", language: language)
            }
            isSyncingNow = false
        }
    }
}

struct MacDictionaryICloudSyncRow: View {
    let defaults: UserDefaults
    let language: AppUILanguage

    @Environment(\.themePalette) private var palette
    @State private var isEnabled = false
    @State private var syncErrorMessage: String?
    @State private var isApplyingToggle = false

    var body: some View {
        Toggle(isOn: toggleBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MacL10n.string("mac.sync.dictTitle", language: language))
                Text(MacL10n.string("mac.sync.dictSubtitle", language: language))
                    .font(TypeStyle.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(palette.accent)
        .disabled(isApplyingToggle)
        .onAppear { reloadFromStore() }
        .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
            reloadFromStore()
        }

        if let syncErrorMessage {
            Text(syncErrorMessage)
                .font(TypeStyle.caption)
                .foregroundStyle(palette.danger)
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard newValue != isEnabled else { return }
                newValue ? enableSync() : disableSync()
            }
        )
    }

    private func reloadFromStore() {
        isEnabled = AppGroupStore(defaults: defaults).personalDictionaryICloudSyncEnabled
    }

    private func enableSync() {
        isApplyingToggle = true
        syncErrorMessage = nil
        Task {
            do {
                try await MacICloudSyncBootstrap.dictionarySync.enableSync()
                reloadFromStore()
            } catch let error as PersonalDictionaryCloudSyncError {
                isEnabled = false
                if case .payloadTooLarge = error {
                    syncErrorMessage = MacL10n.string("mac.sync.error.dictTooLarge", language: language)
                } else {
                    syncErrorMessage = MacL10n.string("mac.sync.error.generic", language: language)
                }
            } catch {
                isEnabled = false
                syncErrorMessage = MacL10n.string("mac.sync.error.generic", language: language)
            }
            isApplyingToggle = false
        }
    }

    private func disableSync() {
        MacICloudSyncBootstrap.dictionarySync.disableSync()
        isEnabled = false
        syncErrorMessage = nil
    }
}
