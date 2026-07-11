// MacSettingsComponents.swift
// OSGKeyboard · Mac
//
// Provider configuration rows for the Settings Form — merged card layout,
// responsive label/control rows, and theme-aware credential chrome.

import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Width-locked inline picker

/// Option for `MacInlinePicker`: a hashable value plus its display label.
struct MacInlinePickerOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String
    var id: Value { value }
}

/// Boxed dropdown trigger that mirrors `.macFieldStyle()` chrome so every picker
/// reads as an editable field: the selected value on the left, a trailing
/// up/down chevron inside the *same* well. Holds a `minWidth` field footprint and
/// expands up to its column when the caller offers width (provider rows).
private struct MacPickerFieldBox: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    var body: some View {
        // Same shape/fill/border rules as `MacFieldStyleModifier` so the dropdown
        // sits flush with the credential text fields around it.
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        HStack(spacing: Spacing.sm) {
            Text(text)
                .font(MacSettingsType.control)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: Spacing.xs)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Spacing.sm)
        // `minWidth` gives short values (e.g. "深色") a proper field footprint;
        // `maxWidth: .infinity` lets fixed-label rows (provider picker) fill their
        // column, while `.fixedSize()` callers (inline rows) hug to the minimum.
        .frame(minWidth: 132, maxWidth: .infinity, minHeight: MacMetrics.settingsControlHeight, alignment: .leading)
        .background(fieldFill, in: shape)
        .overlay(shape.stroke(palette.divider, lineWidth: 0.5))
        .contentShape(shape)
    }

    /// Light mode uses the true text-input white so the box reads as an editable
    /// well; dark mode keeps the elevated grey (mirrors `MacFieldStyleModifier`).
    private var fieldFill: Color {
        #if os(macOS)
        if colorScheme != .dark {
            return Color(nsColor: .textBackgroundColor)
        }
        #endif
        return palette.surfaceElevated
    }
}

/// Dropdown that renders as an editable-looking field (see `MacPickerFieldBox`).
/// A `.menu` `Picker` renders as a native pop-up that ignores `.frame` and drops
/// custom labels; `Menu` instead renders its `label:` as the real control. Kept at
/// `.fixedSize()` so it hugs its content and is right-aligned by the enclosing
/// row's `Spacer`, matching the toggles/status text that share `MacInlineRow`.
struct MacInlinePicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [MacInlinePickerOption<Value>]
    /// When true the boxed field fills its column and is left-aligned — matches
    /// the two-column provider rows (see `MacProviderPickerRow`). When false it
    /// hugs its content so the enclosing row's `Spacer` can right-align it.
    var fillsWidth: Bool = false

    var body: some View {
        if fillsWidth {
            menuButton
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            menuButton
                .fixedSize()
        }
    }

    private var menuButton: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            MacPickerFieldBox(text: selectedLabel)
        }
        // `.button` menu style + `.plain` button style renders the custom
        // `MacPickerFieldBox` label verbatim; `.borderlessButton` would instead
        // draw macOS's own borderless pop-up chrome (accent chevrons, no box).
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? "—"
    }
}

// MARK: - Provider picker

struct MacProviderPickerRow: View {
    let title: String
    let providers: [LLMProvider]
    @Binding var selection: String

    var body: some View {
        MacProviderSettingRow(title: title) {
            Menu {
                ForEach(providers) { provider in
                    Button {
                        selection = provider.id
                    } label: {
                        let name = ProviderDisplayName.name(for: provider.id)
                        if provider.id == selection {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(name)
                        }
                    }
                }
            } label: {
                MacPickerFieldBox(text: selectedName)
            }
            // See `MacInlinePicker`: `.button` + `.plain` keeps our boxed label
            // instead of macOS's borderless pop-up chrome.
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var selectedName: String {
        let id = providers.first { $0.id == selection }?.id ?? selection
        return ProviderDisplayName.name(for: id)
    }
}

// MARK: - Credential field

struct MacCredentialField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecret: Bool = false
    var isMonospaced: Bool = true
    var defaultValue: String?
    var trailing: AnyView?

    @State private var revealed = false

    var body: some View {
        MacProviderSettingRow(title: title) {
            HStack(spacing: Spacing.xs) {
                input
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let defaultValue, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MacSettingsIconButton(systemName: "checkmark", help: "Fill default") {
                        text = defaultValue
                    }
                }

                if let trailing {
                    trailing
                }

                if isSecret {
                    MacSettingsIconButton(
                        systemName: revealed ? "eye.slash" : "eye",
                        help: revealed ? "Hide" : "Show"
                    ) {
                        revealed.toggle()
                    }
                }

                MacSettingsIconButton(systemName: "doc.on.doc", help: "Copy", disabled: text.isEmpty) {
                    #if os(macOS)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private var input: some View {
        Group {
            if isSecret && !revealed {
                SecureField(text: $text, prompt: Text(verbatim: placeholder)) {
                    Text(title)
                }
            } else {
                TextField(text: $text, prompt: Text(verbatim: placeholder)) {
                    Text(title)
                }
            }
        }
        .labelsHidden()
        .autocorrectionDisabled(true)
        .lineLimit(1)
        .truncationMode(.middle)
        .macFieldStyle(monospaced: isMonospaced)
    }
}

// MARK: - Thinking toggle

struct MacProviderThinkingRow: View {
    @Environment(\.themePalette) private var palette

    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        MacProviderSettingRow(title: title, verticalAlignment: .center) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(MacToggleStyle())
                    .accessibilityLabel(title)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Model picker (editable field + fetch icon)

private struct MacModelComboFieldWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct MacProviderModelRow: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let placeholder: String
    @Binding var model: String
    let apiKey: String
    let fetchModels: () async throws -> [String]
    let language: AppUILanguage

    @State private var models: [String] = []
    @State private var isRunning = false
    @State private var message: String?
    @State private var failed = false
    @State private var isDropdownOpen = false
    @State private var fieldWidth: CGFloat = 0

    private let chevronWidth: CGFloat = 28
    private let dropdownMaxHeight: CGFloat = 240

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Match `MacFieldStyleModifier` fill so the combo well sits flush with
    /// neighboring credential fields.
    private var fieldFill: Color {
        #if os(macOS)
        if colorScheme != .dark {
            return Color(nsColor: .textBackgroundColor)
        }
        #endif
        return palette.surfaceElevated
    }

    var body: some View {
        MacProviderSettingRow(title: title) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    comboField

                    MacSettingsIconButton(
                        systemName: "arrow.triangle.2.circlepath",
                        help: MacL10n.string("mac.settings.fetchModels", language: language),
                        disabled: isRunning || trimmedAPIKey.isEmpty
                    ) {
                        isDropdownOpen = false
                        Task { await runFetchModels() }
                    }

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                statusMessage
            }
        }
    }

    /// Editable model id + trailing chevron. Model list is a true popover so the
    /// settings row height stays fixed (not an in-flow panel that grows the card).
    private var comboField: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
        return ZStack(alignment: .trailing) {
            TextField(text: $model, prompt: Text(verbatim: placeholder)) {
                Text(title)
            }
            .labelsHidden()
            .textFieldStyle(.plain)
            .autocorrectionDisabled(true)
            .font(TypeStyle.mono)
            .foregroundStyle(palette.textPrimary)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, Spacing.sm)
            .padding(.trailing, chevronWidth + Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: MacMetrics.settingsControlHeight, alignment: .leading)
            .background(fieldFill, in: shape)
            .overlay(shape.stroke(palette.divider, lineWidth: 0.5))

            Button {
                isDropdownOpen.toggle()
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: chevronWidth, height: MacMetrics.settingsControlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, Spacing.sm)
            .help(MacL10n.string("mac.settings.selectModel", language: language))
            .accessibilityLabel(MacL10n.string("mac.settings.selectModel", language: language))
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: MacModelComboFieldWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(MacModelComboFieldWidthKey.self) { fieldWidth = $0 }
        .popover(isPresented: $isDropdownOpen, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
            dropdownPanel
                .frame(width: max(fieldWidth, 180))
                .padding(Spacing.xs)
        }
    }

    private var dropdownPanel: some View {
        Group {
            if models.isEmpty {
                Text(MacL10n.string("mac.settings.modelsEmptyHint", language: language))
                    .font(MacSettingsType.hint)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(models, id: \.self) { modelId in
                            dropdownRow(modelId)
                        }
                    }
                }
                .frame(maxHeight: dropdownMaxHeight)
            }
        }
    }

    private func dropdownRow(_ modelId: String) -> some View {
        let isSelected = modelId == model
        return Button {
            model = modelId
            message = MacL10n.format(
                "mac.settings.modelSelected",
                language: language,
                modelId
            )
            failed = false
            isDropdownOpen = false
        } label: {
            HStack(spacing: Spacing.sm) {
                Text(modelId)
                    .font(TypeStyle.mono)
                    .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(isSelected ? palette.accentMuted : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let message {
            Text(message)
                .font(MacSettingsType.hint)
                .foregroundStyle(failed ? palette.danger : palette.accent)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func runFetchModels() async {
        guard !trimmedAPIKey.isEmpty else {
            failed = true
            message = SharedL10n.string("providerTools.error.missingAPIKey", language: language)
            return
        }

        isRunning = true
        failed = false
        defer { isRunning = false }

        let outcome = await ProviderToolRunner.runFetchModels(
            runningMessage: MacL10n.string("mac.settings.loadingModels", language: language),
            loadedMessage: { MacL10n.format("mac.settings.modelsLoaded", language: language, $0) },
            emptyMessage: SharedL10n.string("providerTools.error.empty", language: language),
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

// MARK: - Connection validate

struct MacProviderToolsRow: View {
    @Environment(\.themePalette) private var palette

    let title: String
    let validate: () async throws -> Void
    let language: AppUILanguage

    @State private var isRunning = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        MacProviderSettingRow(title: title) {
            HStack(alignment: .center, spacing: Spacing.sm) {
                MacSettingsToolButton(
                    title: MacL10n.string("mac.settings.validate", language: language),
                    disabled: isRunning
                ) {
                    Task { await runValidate() }
                }

                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else if let message {
                    Text(message)
                        .font(MacSettingsType.hint)
                        .foregroundStyle(failed ? palette.danger : palette.accent)
                        .lineLimit(3)
                        .truncationMode(.tail)
                }
            }
        }
    }

    @MainActor
    private func runValidate() async {
        isRunning = true
        failed = false
        defer { isRunning = false }

        let outcome = await ProviderToolRunner.runValidate(
            runningMessage: MacL10n.string("mac.settings.validating", language: language),
            successMessage: MacL10n.string("mac.settings.validateSuccess", language: language),
            validate: validate
        )
        message = outcome.message
        failed = outcome.failed
    }
}

// MARK: - Caption note row

struct MacProviderNoteRow: View {
    @Environment(\.themePalette) private var palette

    let text: String

    var body: some View {
        Text(text)
            .font(MacSettingsType.hint)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: MacMetrics.settingsRowMinHeight, alignment: .leading)
            .padding(.horizontal, MacMetrics.settingsCardInset)
    }
}
