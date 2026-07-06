// PersonalDictionaryICloudSyncRow.swift
// OSGKeyboard · Main App
//
// Settings-row toggle for mirroring the personal dictionary through
// iCloud Key-Value Store. Lives in Settings → 词库与润色.

import SwiftUI
import OSGKeyboardShared

@MainActor
struct PersonalDictionaryICloudSyncRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @State private var isEnabled: Bool = AppGroupStore().personalDictionaryICloudSyncEnabled
    @State private var syncErrorMessage: String?
    @State private var isApplyingToggle = false

    private let store = AppGroupStore()

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Toggle(isOn: toggleBinding) {
                Text("settings.personalDictionary.iCloudSync.settingsTitle")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
            }
            .tint(palette.accent)
            .disabled(isApplyingToggle)

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

    private func reloadFromStore() {
        isEnabled = store.personalDictionaryICloudSyncEnabled
    }

    private func enableSync() {
        isApplyingToggle = true
        syncErrorMessage = nil
        Task {
            do {
                try await PersonalDictionaryCloudSync.shared.enableSync()
                reloadFromStore()
            } catch let error as PersonalDictionaryCloudSyncError {
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
        PersonalDictionaryCloudSync.shared.disableSync()
        isEnabled = false
        syncErrorMessage = nil
    }

    private func localizedSyncError(_ error: PersonalDictionaryCloudSyncError) -> String {
        switch error {
        case .payloadTooLarge:
            return AppL10n.string("settings.personalDictionary.iCloudSync.error.tooLarge")
        case .encodeFailed, .decodeFailed:
            return AppL10n.string("settings.personalDictionary.iCloudSync.error.generic")
        }
    }
}
