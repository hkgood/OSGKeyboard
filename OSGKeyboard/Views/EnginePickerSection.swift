// EnginePickerSection.swift
// OSGKeyboard · Main App
//
// Engine picker — Local (on-device ASR) vs
// Cloud (ASR + optional LLM polish via the user's API).

import SwiftUI
import OSGKeyboardShared

struct EnginePickerSection<ConfigurationRows: View>: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var config: ProviderConfig
    private let configurationRows: ConfigurationRows

    init(
        config: ProviderConfig,
        @ViewBuilder configurationRows: () -> ConfigurationRows
    ) {
        self.config = config
        self.configurationRows = configurationRows()
    }

    var body: some View {
        CardSection("settings.engine.title") {
            VStack(spacing: 0) {
                engineOptionRow(
                    id: "local",
                    title: AppL10n.string("settings.engine.local.title"),
                    subtitle: localSubtitle
                )
                Divider().background(palette.divider)
                engineOptionRow(
                    id: "cloud",
                    title: AppL10n.string("settings.engine.cloud.title"),
                    subtitle: AppL10n.string("settings.engine.cloud.subtitle")
                )
                configurationRows
            }
            .surfaceCard()
        }
    }

    private var localSubtitle: String {
        AppL10n.string("settings.engine.local.legacy")
    }

    private func engineOptionRow(
        id: String,
        title: String,
        subtitle: String
    ) -> some View {
        let isSelected = config.engineMode == id
        return Button {
            guard config.engineMode != id else { return }
            selectEngine(id)
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeStyle.body)
                        .foregroundStyle(isSelected ? palette.accent : palette.textPrimary)
                    Text(subtitle)
                        .font(TypeStyle.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .settingsListRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectEngine(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            config.engineMode = id
            if id == "cloud" {
                config.modeId = "polish"
            }
        }
    }

}

extension EnginePickerSection where ConfigurationRows == EmptyView {
    init(config: ProviderConfig) {
        self.init(config: config) {
            EmptyView()
        }
    }
}
