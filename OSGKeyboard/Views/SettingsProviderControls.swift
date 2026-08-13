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
    let providerIdentity: String
    let endpointIdentity: String
    let credentialIdentity: String
    let makeFetchModelsRequest: @MainActor () -> ProviderToolRequest<[String]>

    @State private var models: [String] = []
    @State private var isRunning = false
    @State private var message: String?
    @State private var failed = false
    @State private var requestCoordinator = ProviderToolRequestCoordinator()

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
        .onChange(of: providerIdentity) { _, _ in invalidateRequest() }
        .onChange(of: endpointIdentity) { _, _ in invalidateRequest() }
        .onChange(of: credentialIdentity) { _, _ in invalidateRequest() }
        .onChange(of: model) { _, _ in invalidateRequestIfRunning() }
        .onDisappear { invalidateRequest() }
    }

    /// Editable model id + trailing menu chevron in one well (same chrome as
    /// Mac `MacPickerFieldBox`). Chevron is overlaid so it stays inside the border.
    private var comboField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        let chevronWidth: CGFloat = 28
        return ZStack(alignment: .trailing) {
            TextField(placeholder, text: editableModelBinding)
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
                            invalidateRequest()
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
            runFetchModels()
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

    private var editableModelBinding: Binding<String> {
        Binding(
            get: { model },
            set: { newValue in
                invalidateRequest()
                model = newValue
            }
        )
    }

    @MainActor
    private func runFetchModels() {
        let request = makeFetchModelsRequest()
        let currentModel = model
        let runningMessage = AppL10n.string("settings.provider.loadingModels")
        let emptyMessage = SharedL10n.string("providerTools.error.empty")

        isRunning = true
        failed = false
        message = runningMessage

        requestCoordinator.start(
            providerIdentity: request.providerIdentity,
            operation: {
                await ProviderToolRunner.runFetchModels(
                    runningMessage: runningMessage,
                    loadedMessage: { AppL10n.format("settings.provider.modelsLoaded", $0) },
                    emptyMessage: emptyMessage,
                    currentModel: currentModel,
                    fetchModels: request.operation
                )
            },
            commit: { outcome in
                isRunning = false
                switch outcome {
                case .cancelled:
                    message = nil
                    failed = false
                case .completed(let state, let selectedModel):
                    models = state.models
                    message = state.message
                    failed = state.failed
                    if let selectedModel {
                        model = selectedModel
                    }
                }
            }
        )
    }

    @MainActor
    private func invalidateRequest() {
        requestCoordinator.invalidate()
        isRunning = false
        message = nil
        failed = false
    }

    @MainActor
    private func invalidateRequestIfRunning() {
        guard requestCoordinator.isRunning else { return }
        invalidateRequest()
    }
}

// MARK: - Connection validate only

struct SettingsProviderToolsRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let providerIdentity: String
    let endpointIdentity: String
    let credentialIdentity: String
    let modelIdentity: String
    let makeValidateRequest: @MainActor () -> ProviderToolRequest<Void>

    @State private var isRunning = false
    @State private var message: String?
    @State private var failed = false
    @State private var requestCoordinator = ProviderToolRequestCoordinator()

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
                runValidate()
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
        .onChange(of: providerIdentity) { _, _ in invalidateRequest() }
        .onChange(of: endpointIdentity) { _, _ in invalidateRequest() }
        .onChange(of: credentialIdentity) { _, _ in invalidateRequest() }
        .onChange(of: modelIdentity) { _, _ in invalidateRequest() }
        .onDisappear { invalidateRequest() }
    }

    @MainActor
    private func runValidate() {
        let request = makeValidateRequest()
        let runningMessage = AppL10n.string("api.test.running")
        let successMessage = AppL10n.string("api.test.success")

        isRunning = true
        failed = false
        message = runningMessage

        requestCoordinator.start(
            providerIdentity: request.providerIdentity,
            operation: {
                await ProviderToolRunner.runValidate(
                    runningMessage: runningMessage,
                    successMessage: successMessage,
                    validate: request.operation
                )
            },
            commit: { outcome in
                isRunning = false
                switch outcome {
                case .cancelled:
                    message = nil
                    failed = false
                case .completed(let state):
                    message = state.message
                    failed = state.failed
                }
            }
        )
    }

    @MainActor
    private func invalidateRequest() {
        requestCoordinator.invalidate()
        isRunning = false
        message = nil
        failed = false
    }
}
