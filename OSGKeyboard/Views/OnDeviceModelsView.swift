// OnDeviceModelsView.swift
// OSGKeyboard · Main App
//
// Full-page model download manager. The same `OnDeviceModelsContent`
// is also embedded inline in `SettingsView` so users see manual
// download controls without drilling into About.

import SwiftUI
import OSGKeyboardShared

/// Inline + full-page body for on-device model downloads.
struct OnDeviceModelsContent: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var manager: ModelManager
    @Binding var pendingDownload: OnDeviceModel?

    init(
        manager: ModelManager = .shared,
        pendingDownload: Binding<OnDeviceModel?>
    ) {
        _manager = ObservedObject(wrappedValue: manager)
        _pendingDownload = pendingDownload
    }

    var body: some View {
        Group {
            ForEach(Array(OnDeviceModel.allCases.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    Divider().background(palette.divider)
                }
                OnDeviceModelListRow(
                    model: model,
                    manager: manager,
                    pendingDownload: $pendingDownload
                )
            }
        }
    }
}

// MARK: - Model row

struct OnDeviceModelListRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let model: OnDeviceModel
    @ObservedObject var manager: ModelManager
    @Binding var pendingDownload: OnDeviceModel?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(model.listTitle)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Spacing.xs)
            ModelListActionButton(
                model: model,
                manager: manager,
                pendingDownload: $pendingDownload
            )
        }
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
    }
}

// MARK: - Action button

struct ModelListActionButton: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let model: OnDeviceModel
    @ObservedObject var manager: ModelManager
    @Binding var pendingDownload: OnDeviceModel?

    var body: some View {
        let state = manager.states[model]?.download ?? .notDownloaded
        Button(action: { performAction(for: state) }) {
            Text(buttonTitle(for: state))
                .font(TypeStyle.caption)
                .foregroundStyle(buttonColor(for: state))
                .monospacedDigit()
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 5)
                .background(buttonBackground(for: state), in: Capsule())
                .overlay(
                    Capsule().stroke(buttonBorder(for: state), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func performAction(for state: ModelDownloadState) {
        switch state {
        case .notDownloaded, .failed:
            pendingDownload = model
        case .downloading:
            manager.cancelDownload(model)
        case .downloaded:
            manager.deleteModel(model)
        }
    }

    private func buttonTitle(for state: ModelDownloadState) -> String {
        let size = model.compactSizeLabel
        switch state {
        case .notDownloaded, .failed:
            return AppL10n.format("settings.models.action.downloadSize %@", size)
        case .downloading(let progress):
            return AppL10n.format(
                "settings.models.action.downloadingPercent %lld",
                Int((progress * 100).rounded())
            )
        case .downloaded:
            return AppL10n.format("settings.models.action.deleteSize %@", size)
        }
    }

    private func buttonColor(for state: ModelDownloadState) -> Color {
        switch state {
        case .notDownloaded, .failed:
            return palette.textOnAccent
        case .downloading:
            return palette.accent
        case .downloaded:
            return palette.warning
        }
    }

    private func buttonBackground(for state: ModelDownloadState) -> Color {
        switch state {
        case .notDownloaded, .failed:
            return palette.accent
        case .downloading:
            return palette.accent.opacity(0.12)
        case .downloaded:
            return palette.warning.opacity(0.1)
        }
    }

    private func buttonBorder(for state: ModelDownloadState) -> Color {
        switch state {
        case .notDownloaded, .failed:
            return .clear
        case .downloading:
            return palette.accent.opacity(0.35)
        case .downloaded:
            return palette.warning.opacity(0.35)
        }
    }
}

// MARK: - Full page

struct OnDeviceModelsView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @StateObject private var manager = ModelManager.shared
    @State private var pendingDownload: OnDeviceModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                OnDeviceModelsContent(manager: manager, pendingDownload: $pendingDownload)
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .background(palette.background.ignoresSafeArea())
        .navigationTitle("settings.models.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pendingDownload) { model in
            DownloadConfirmSheet(model: model) {
                pendingDownload = nil
                manager.startDownload(model)
            }
        }
    }
}
