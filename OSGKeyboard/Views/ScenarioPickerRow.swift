// ScenarioPickerRow.swift
// OSGKeyboard · Main App
//
// Single-row polish scenario picker. Maps menu choices to
// `ProviderConfig.polishScenarioId`. Custom scenario uses the existing
// system prompt editor (linked from Settings when selected).

import SwiftUI
import OSGKeyboardShared

struct ScenarioPickerRow: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @ObservedObject var config: ProviderConfig

    var isVisible: Bool = true

    var body: some View {
        if isVisible {
            HStack {
                Text("settings.polishScenario.title")
                    .font(TypeStyle.body)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Menu {
                    ForEach(PolishScenarioCatalog.all) { scenario in
                        Button {
                            config.polishScenarioId = scenario.id
                        } label: {
                            if config.polishScenarioId == scenario.id {
                                Label(displayLabel(for: scenario), systemImage: "checkmark")
                            } else {
                                Text(displayLabel(for: scenario))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currentLabel)
                            .font(TypeStyle.body)
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: SettingsListMetrics.singleLineMinHeight)
        }
    }

    private var currentLabel: String {
        displayLabel(for: PolishScenarioCatalog.resolve(config.polishScenarioId))
    }

    private func displayLabel(for scenario: PolishScenario) -> String {
        PolishScenarioCatalog.displayName(for: scenario.id, language: config.uiLanguage)
    }
}
