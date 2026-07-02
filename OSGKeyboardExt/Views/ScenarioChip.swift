// ScenarioChip.swift
// OSGKeyboard · Keyboard Extension
//
// Compact chip on the keyboard top bar for quick polish scenario
// switching. Same Menu pattern as `TranslationChip`.

import SwiftUI
import OSGKeyboardShared

struct ScenarioChip: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    @ObservedObject var state: KeyboardViewController.State

    var body: some View {
        Menu {
            ForEach(PolishScenarioCatalog.all) { scenario in
                Button {
                    state.setPolishScenarioId(scenario.id)
                } label: {
                    if scenario.id == state.polishScenarioId {
                        Label(displayLabel(for: scenario), systemImage: "checkmark")
                    } else {
                        Text(displayLabel(for: scenario))
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .accessibilityLabel(ExtL10n.text("keyboard.scenario.a11y"))
        .accessibilityHint(ExtL10n.text("keyboard.scenario.a11yHint"))
    }

    private var label: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.bubble")
            Text(chipText)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .font(TypeStyle.caption2)
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, Spacing.xs + 2)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(palette.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(palette.divider, lineWidth: 0.5))
    }

    private var chipText: String {
        PolishScenarioCatalog.chipLabel(for: state.polishScenarioId)
    }

    private func displayLabel(for scenario: PolishScenario) -> String {
        PolishScenarioCatalog.displayName(for: scenario.id)
    }
}
