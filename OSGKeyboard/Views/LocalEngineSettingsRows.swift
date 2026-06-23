// LocalEngineSettingsRows.swift
// OSGKeyboard · Main App
//
// Grouped "local models" block for the local engine settings card.
// Speech recognition row with a compact readiness summary in the header.

import SwiftUI
import OSGKeyboardShared

// MARK: - Local models group (scheme A)

struct LocalModelsGroup: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    @ObservedObject var manager: ModelManager
    @Binding var pendingDownload: OnDeviceModel?

    var body: some View {
        speechRow
    }

    // MARK: Speech row

    private var speechRow: some View {
        HStack(spacing: Spacing.xs) {
            Text("settings.localModels.speechRole")
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            speechBackendMenu
            Spacer(minLength: Spacing.xs)
            speechTrailing
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }

    private var speechBackendMenu: some View {
        Menu {
            ForEach(LocalASRBackend.allCases) { backend in
                Button {
                    config.localASRBackend = backend
                } label: {
                    if backend == config.localASRBackend {
                        Label(
                            AppL10n.string(backend.labelKey),
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(AppL10n.string(backend.labelKey))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(AppL10n.string(config.localASRBackend.labelKey))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var speechTrailing: some View {
        if config.localASRBackend == .speechAnalyzer {
            builtInBadge
        } else {
            ModelListActionButton(
                model: .qwen3ASR,
                manager: manager,
                pendingDownload: $pendingDownload
            )
        }
    }

    // MARK: Helpers

    private var builtInBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("settings.localModels.builtIn")
                .font(TypeStyle.caption)
        }
        .foregroundStyle(palette.accent)
    }
}
