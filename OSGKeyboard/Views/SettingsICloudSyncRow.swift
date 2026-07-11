// SettingsICloudSyncRow.swift
// OSGKeyboard · Main App
//
// Settings-row toggle for mirroring user preferences through iCloud KVS.

import SwiftUI
import OSGKeyboardShared

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
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Toggle(isOn: toggleBinding) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("settings.appSettings.iCloudSync.title")
                        .font(TypeStyle.body)
                        .foregroundStyle(palette.textPrimary)
                    Text("settings.appSettings.iCloudSync.subtitle")
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(palette.accent)
            .disabled(isApplyingToggle)

            if isEnabled {
                Button {
                    syncNow()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Text(syncButtonTitleKey)
                            .font(TypeStyle.caption)
                        Spacer(minLength: 0)
                        if isSyncingNow {
                            ProgressView()
                                .controlSize(.mini)
                        } else if showSyncedConfirmation {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    // Fill the row so the whole strip is tappable, not just
                    // the caption glyphs (previously easy to miss).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .disabled(isSyncingNow || isApplyingToggle)
                .padding(.top, Spacing.xxs)
            }

            if let syncErrorMessage {
                Text(syncErrorMessage)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.xxs)
            }
        }
        .settingsListRow(alignment: .leading)
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

    private var syncButtonTitleKey: LocalizedStringKey {
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
                    CloudSyncContext.shared.settingsSyncService.disableSync()
                    isEnabled = false
                    syncErrorMessage = localizedDictionarySyncError(error)
                    isApplyingToggle = false
                    return
                }
                reloadFromStore()
            } catch let error as SettingsCloudSyncError {
                isEnabled = false
                syncErrorMessage = localizedSyncError(error)
            } catch {
                isEnabled = false
                syncErrorMessage = error.localizedDescription
            }
            isApplyingToggle = false
        }
    }

    private func disableSync() {
        CloudSyncContext.shared.settingsSyncService.disableSync()
        isEnabled = false
        syncErrorMessage = nil
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
