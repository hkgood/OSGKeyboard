// SettingsICloudSyncRow.swift
// OSGKeyboard · Main App
//
// Settings-row toggle for mirroring user preferences through iCloud KVS.

import OSGKeyboardShared
import SwiftUI

@MainActor
struct SettingsICloudSyncRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @State private var isEnabled: Bool = AppGroupStore().settingsICloudSyncEnabled
    @State private var syncErrorMessage: String?
    @State private var isApplyingToggle = false
    @State private var isSyncingNow = false
    /// Transient success flag: shows a brief "已同步" confirmation so a fast
    /// sync gives visible feedback instead of a spinner that flashes once.
    @State private var showSyncedConfirmation = false

    private let store = AppGroupStore()

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: toggleBinding) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(AppL10n.string("settings.appSettings.iCloudSync.title"))
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                    Text(AppL10n.string("settings.appSettings.iCloudSync.subtitle"))
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(palette.accent)
            .disabled(isApplyingToggle)
            .settingsListRow(alignment: .leading)

            if isEnabled {
                Divider().background(palette.divider)

                Button {
                    syncNow()
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.sm) {
                            Text(AppL10n.string(syncButtonTitleKey))
                                .font(TypeStyle.body)
                            Spacer(minLength: Spacing.xs)
                            if isSyncingNow {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(
                                    systemName: showSyncedConfirmation
                                        ? "checkmark"
                                        : "arrow.triangle.2.circlepath"
                                )
                                .font(.system(size: 14, weight: .semibold))
                            }
                        }

                        if let syncErrorMessage {
                            Text(syncErrorMessage)
                                .font(TypeStyle.caption2)
                                .foregroundStyle(palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Fill the row so the whole strip is tappable, not just
                    // the caption glyphs (previously easy to miss).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .settingsListRow(alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .disabled(isSyncingNow || isApplyingToggle)
            }
        }
        .onAppear { reloadFromStore() }
        .onReceive(
            NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)
        ) { _ in
            reloadFromStore()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .personalDictionaryDidSyncFromCloud)
        ) { _ in
            reloadFromStore()
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { newValue in
                guard newValue != isEnabled else { return }
                if newValue {
                    enableSync()
                } else {
                    disableSync()
                }
            }
        )
    }

    private var syncButtonTitleKey: String {
        if isSyncingNow {
            return "settings.appSettings.iCloudSync.syncing"
        }
        if showSyncedConfirmation {
            return "settings.appSettings.iCloudSync.synced"
        }
        return "settings.appSettings.iCloudSync.syncNow"
    }

    private func reloadFromStore() {
        isEnabled = store.settingsICloudSyncEnabled
    }

    private func enableSync() {
        isApplyingToggle = true
        syncErrorMessage = nil
        Task {
            do {
                try await CloudSyncContext.shared.settingsSyncService.enableSync()
                do {
                    try await CloudSyncContext.shared.dictionarySyncService.enableSync()
                } catch let error as PersonalDictionaryCloudSyncError {
                    do {
                        try CloudSyncContext.shared.settingsSyncService.disableSync()
                        isEnabled = false
                        syncErrorMessage = localizedDictionarySyncError(error)
                    } catch let rollbackError as SettingsCloudSyncError {
                        reloadFromStore()
                        syncErrorMessage = localizedSyncError(rollbackError)
                    } catch {
                        reloadFromStore()
                        syncErrorMessage = error.localizedDescription
                    }
                    isApplyingToggle = false
                    return
                }
                reloadFromStore()
            } catch let error as SettingsCloudSyncError {
                reloadFromStore()
                syncErrorMessage = localizedSyncError(error)
            } catch {
                reloadFromStore()
                syncErrorMessage = error.localizedDescription
            }
            isApplyingToggle = false
        }
    }

    private func disableSync() {
        syncErrorMessage = nil
        isApplyingToggle = true
        do {
            try CloudSyncContext.shared.settingsSyncService.disableSync()
            reloadFromStore()
        } catch let error as SettingsCloudSyncError {
            reloadFromStore()
            syncErrorMessage = localizedSyncError(error)
        } catch {
            reloadFromStore()
            syncErrorMessage = error.localizedDescription
        }
        isApplyingToggle = false
    }

    private func syncNow() {
        guard !isSyncingNow else { return }
        isSyncingNow = true
        showSyncedConfirmation = false
        syncErrorMessage = nil
        Task {
            do {
                try await CloudSyncContext.shared.syncNow()
                isSyncingNow = false
                withAnimation { showSyncedConfirmation = true }
                // Auto-dismiss the confirmation so the label returns to
                // its default "立即同步" state.
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                withAnimation { showSyncedConfirmation = false }
            } catch {
                isSyncingNow = false
                syncErrorMessage = AppL10n.string("settings.appSettings.iCloudSync.error.generic")
            }
        }
    }

    private func localizedSyncError(_ error: SettingsCloudSyncError) -> String {
        switch error {
        case .encodeFailed, .decodeFailed:
            return AppL10n.string("settings.appSettings.iCloudSync.error.generic")
        case .credentialMigrationFailed:
            return AppL10n.string("settings.appSettings.iCloudSync.error.generic")
        }
    }

    private func localizedDictionarySyncError(_ error: PersonalDictionaryCloudSyncError) -> String {
        switch error {
        case .payloadTooLarge:
            return AppL10n.string("settings.personalDictionary.iCloudSync.error.tooLarge")
        case .encodeFailed, .decodeFailed:
            return AppL10n.string("settings.personalDictionary.iCloudSync.error.generic")
        }
    }
}
