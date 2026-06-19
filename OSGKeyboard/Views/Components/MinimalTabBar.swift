// MinimalTabBar.swift
// OSGKeyboard · Main App
//
// Bottom tab bar — three Material icons, no labels.
// Capsule uses iOS 26 Liquid Glass (.regular.interactive) so content
// behind the dock refracts through on scroll.

import SwiftUI
import OSGKeyboardShared

enum AppTab: Int, CaseIterable {
    case keyboard
    case history
    case settings

    var icon: MaterialIconName {
        switch self {
        case .keyboard: return .keyboard
        case .history: return .menuBook
        case .settings: return .settings
        }
    }

    var accessibilityKey: LocalizedStringKey {
        switch self {
        case .keyboard: return "tab.keyboard"
        case .history: return "tab.history"
        case .settings: return "tab.settings"
        }
    }
}

struct MinimalTabBar: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(Motion.quick) { selection = tab }
                } label: {
                    MaterialIcon(
                        name: tab.icon,
                        size: 24
                    )
                    .foregroundStyle(selection == tab ? palette.accent : palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityKey)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(maxWidth: 252)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, Spacing.xs)
    }
}
