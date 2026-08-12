// MinimalTabBar.swift
// OSGKeyboard · Main App
//
// Bottom tab bar — three icons, no labels.
// Capsule uses iOS 26 Liquid Glass (.regular.interactive) so content
// behind the dock refracts through on scroll.
// History + dictionary live as Home cards (not dock tabs).

import SwiftUI
import OSGKeyboardShared

enum AppTab: Int, CaseIterable {
    case keyboard
    case styles
    case settings

    var icon: MaterialIconName {
        switch self {
        case .keyboard: return .keyboard
        case .styles: return .menuBook // unused — styles uses SF Symbol
        case .settings: return .settings
        }
    }

    /// SF Symbol overrides shared with the Mac and iPad sidebars.
    var sfSymbol: String? {
        switch self {
        case .styles: return "text.badge.star"
        default: return nil
        }
    }

    var accessibilityKey: LocalizedStringKey {
        switch self {
        case .keyboard: return "tab.keyboard"
        case .styles: return "tab.styles"
        case .settings: return "tab.settings"
        }
    }

    /// Sidebar label for iPad `NavigationSplitView` (SF Symbol + title).
    var sidebarTitle: LocalizedStringKey { accessibilityKey }

    var sidebarSystemImage: String {
        switch self {
        case .keyboard: return "house"
        case .styles: return "text.badge.star"
        case .settings: return "gearshape"
        }
    }
}

struct MinimalTabBar: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectionGlassNamespace
    @Binding var selection: AppTab

    var body: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button {
                        withAnimation(Motion.soft) {
                            selection = tab
                        }
                    } label: {
                        Group {
                            if let sfSymbol = tab.sfSymbol {
                                Image(systemName: sfSymbol)
                                    .font(.system(size: 20, weight: .regular))
                            } else {
                                MaterialIcon(name: tab.icon, size: 24)
                            }
                        }
                        .foregroundStyle(tabIconColor(for: tab))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background {
                            if selection == tab {
                                // Capsule, not circle: a circle would inscribe to the
                                // smaller edge and leave the tab slot looking empty.
                                Color.clear
                                    .frame(width: 52, height: 44)
                                    .glassEffect(
                                        .regular
                                            .tint(palette.accent.opacity(0.18))
                                            .interactive(),
                                        in: .capsule
                                    )
                                    .glassEffectID(
                                        "main-tab-selection",
                                        in: selectionGlassNamespace
                                    )
                                    .glassEffectTransition(.matchedGeometry)
                                    .matchedGeometryEffect(
                                        id: "main-tab-selection",
                                        in: selectionGlassNamespace
                                    )
                            }
                        }
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
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, Spacing.xs)
    }

    private func tabIconColor(for tab: AppTab) -> Color {
        if selection == tab { return palette.accent }
        // 未选中：浅色模式更深、深色模式更亮，提升 dock 可读性。
        return colorScheme == .dark
            ? Color(white: 0.76)
            : palette.textSecondary
    }
}
