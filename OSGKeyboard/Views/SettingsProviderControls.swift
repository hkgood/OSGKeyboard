// SettingsProviderControls.swift
// OSGKeyboard · Main App
//
// OpenLess-style setting rows for provider credentials and tools. Compact iOS
// stacks label above control; regular-width iPad keeps label/control in one row.

import SwiftUI
import OSGKeyboardShared

struct SettingsProviderRow<Content: View>: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 8) {
                label
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingsListRow()
        } else {
            HStack(alignment: .center, spacing: Spacing.lg) {
                label
                    .frame(width: 150, alignment: .leading)
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingsListRow()
        }
    }

    private var label: some View {
        Text(title)
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
    }
}

struct SettingsCredentialRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecret: Bool = false
    var isMonospaced: Bool = false
    var defaultValue: String?
    var trailing: AnyView?

    @State private var revealed = false

    var body: some View {
        SettingsProviderRow(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Spacing.xs) {
                    input
                    if let defaultValue, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        iconButton(systemName: "checkmark", label: "settings.provider.fillDefault") {
                            text = defaultValue
                        }
                    }
                    if let trailing {
                        trailing
                    }
                    if isSecret {
                        iconButton(systemName: revealed ? "eye.slash" : "eye", label: revealed ? "api.key.hide" : "api.key.show") {
                            revealed.toggle()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        Group {
            if isSecret && !revealed {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .keyboardType(.asciiCapable)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .font(isMonospaced ? TypeStyle.mono : TypeStyle.caption)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, Spacing.sm)
        .frame(minHeight: 38)
        .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }

    private func iconButton(systemName: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 38, height: 38)
                .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                        .stroke(palette.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Editable model field + fetch icon

/// Model id: type freely, or fetch then pick from the trailing dropdown.
struct SettingsModelPickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: String
    let placeholder: String
    @Binding var model: String
    let fetchModels: () async throws -> [String]

    @State private var models: [String] = []
    @State private var isRunning = false
    @State private var message: String?
    @State private var failed = false

    private let controlHeight: CGFloat = 38

    var body: some View {
        SettingsProviderRow(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Spacing.xs) {
                    comboField
                    refreshButton
                }

                if let message {
                    Text(message)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(failed ? palette.danger : palette.accent)
                        .lineLimit(3)
                }
            }
        }
    }

    /// Editable model id + trailing menu chevron in one well (same chrome as
    /// Mac `MacPickerFieldBox`). Chevron is overlaid so it stays inside the border.
    private var comboField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        let chevronWidth: CGFloat = 28
        return ZStack(alignment: .trailing) {
            TextField(placeholder, text: $model)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .font(TypeStyle.mono)
                .foregroundStyle(palette.textPrimary)
                .padding(.leading, Spacing.sm)
                .padding(.trailing, chevronWidth + Spacing.sm)
                .frame(maxWidth: .infinity, minHeight: controlHeight, alignment: .leading)
                .background(palette.surfaceElevated, in: shape)
                .overlay(shape.stroke(palette.divider, lineWidth: 0.5))

            Menu {
                if models.isEmpty {
                    Button(AppL10n.string("settings.provider.modelsEmptyHint")) {}
                        .disabled(true)
                } else {
                    ForEach(models, id: \.self) { modelId in
                        Button {
                            model = modelId
                            message = AppL10n.format("settings.provider.modelSelected", modelId)
                            failed = false
                        } label: {
                            if modelId == model {
                                Label(modelId, systemImage: "checkmark")
                            } else {
                                Text(modelId)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: chevronWidth, height: controlHeight)
                    .contentShape(Rectangle())
            }
            .padding(.trailing, Spacing.sm)
            .accessibilityLabel(AppL10n.string("settings.provider.selectModel"))
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await runFetchModels() }
        } label: {
            Group {
                if isRunning {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(width: controlHeight, height: controlHeight)
            .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                    .stroke(palette.divider, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .accessibilityLabel(AppL10n.string("settings.provider.fetchModels"))
    }

    @MainActor
    private func runFetchModels() async {
        isRunning = true
        failed = false
        defer { isRunning = false }

        let outcome = await ProviderToolRunner.runFetchModels(
            runningMessage: AppL10n.string("settings.provider.loadingModels"),
            loadedMessage: { AppL10n.format("settings.provider.modelsLoaded", $0) },
            emptyMessage: SharedL10n.string("providerTools.error.empty"),
            currentModel: model,
            fetchModels: fetchModels
        )
        models = outcome.state.models
        message = outcome.state.message
        failed = outcome.state.failed
        if let selected = outcome.selectedModel {
            model = selected
        }
    }
}

// MARK: - Connection validate only

struct SettingsProviderToolsRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let validate: () async throws -> Void

    @State private var isRunning = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text(AppL10n.string("settings.provider.tools"))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)

            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            } else if let message {
                Text(message)
                    .font(TypeStyle.caption2)
                    .foregroundStyle(failed ? palette.danger : palette.accent)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Button {
                Task { await runValidate() }
            } label: {
                Text(AppL10n.string("settings.provider.validate"))
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, Spacing.md)
                    .frame(minHeight: 34)
                    .background(palette.surfaceElevated, in: RoundedRectangle(cornerRadius: Radius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.medium)
                            .stroke(palette.divider, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isRunning)
        }
        .settingsListRow()
    }

    @MainActor
    private func runValidate() async {
        isRunning = true
        failed = false
        defer { isRunning = false }

        let outcome = await ProviderToolRunner.runValidate(
            runningMessage: AppL10n.string("api.test.running"),
            successMessage: AppL10n.string("api.test.success"),
            validate: validate
        )
        message = outcome.message
        failed = outcome.failed
    }
}
