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
                        if isSyncingNow {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("settings.appSettings.iCloudSync.syncNow")
                            .font(TypeStyle.caption)
                    }
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
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight, alignment: .leading)
        .onAppear { reloadFromStore() }
        .onReceive(
            NotificationCenter.default.publisher(for: .settingsDidSyncFromCloud)
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

    private func reloadFromStore() {
        isEnabled = store.settingsICloudSyncEnabled
    }

    private func enableSync() {
        isApplyingToggle = true
        syncErrorMessage = nil
        Task {
            do {
                try await CloudSyncContext.shared.settingsSyncService.enableSync()
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
        isSyncingNow = true
        syncErrorMessage = nil
        Task {
            do {
                try await CloudSyncContext.shared.syncNow()
            } catch {
                syncErrorMessage = AppL10n.string("settings.appSettings.iCloudSync.error.generic")
            }
            isSyncingNow = false
        }
    }

    private func localizedSyncError(_ error: SettingsCloudSyncError) -> String {
        switch error {
        case .encodeFailed, .decodeFailed:
            return AppL10n.string("settings.appSettings.iCloudSync.error.generic")
        }
    }
}
