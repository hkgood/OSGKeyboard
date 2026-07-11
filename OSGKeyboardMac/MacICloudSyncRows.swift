// MacICloudSyncRows.swift
// OSGKeyboard · Mac
//
// iCloud sync toggle for settings, history, API keys, and personal
// dictionary — same KVS keys and merge rules as the iOS settings page.

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
        MacProviderSettingRow(
            title: MacL10n.string("mac.sync.settingsTitle", language: language),
            verticalAlignment: .center
        ) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Toggle("", isOn: toggleBinding)
                    .labelsHidden()
                    .toggleStyle(MacToggleStyle())
                    .disabled(isApplyingToggle)
                Text(MacL10n.string("mac.sync.settingsSubtitle", language: language))
                    .font(TypeStyle.caption2)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { reloadFromStore() }
        .onReceive(NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)) { _ in
            reloadFromStore()
        }
        .onReceive(NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)) { _ in
            reloadFromStore()
        }

        if isEnabled {
            HStack(spacing: Spacing.xs) {
                MacSettingsToolButton(
                    title: MacL10n.string("mac.sync.syncNow", language: language),
                    disabled: isSyncingNow || isApplyingToggle
                ) {
                    syncNow()
                }
                if isSyncingNow { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MacMetrics.settingsCardInset)
            .padding(.bottom, Spacing.sm)
        }

        if let syncErrorMessage {
            Text(syncErrorMessage)
                .font(MacSettingsType.hint)
                .foregroundStyle(palette.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MacMetrics.settingsCardInset)
                .padding(.bottom, Spacing.sm)
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
                do {
                    try await MacICloudSyncBootstrap.dictionarySync.enableSync()
                } catch let error as PersonalDictionaryCloudSyncError {
                    MacICloudSyncBootstrap.settingsSync.disableSync()
                    isEnabled = false
                    if case .payloadTooLarge = error {
                        syncErrorMessage = MacL10n.string("mac.sync.error.dictTooLarge", language: language)
                    } else {
                        syncErrorMessage = MacL10n.string("mac.sync.error.generic", language: language)
                    }
                    isApplyingToggle = false
                    return
                }
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
