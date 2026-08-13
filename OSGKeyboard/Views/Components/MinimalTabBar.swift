// MinimalTabBar.swift
// OSGKeyboard · Main App
//
// Bottom tab bar — icon + label for Home / Skills / Styles / Settings.
// The dock capsule is iOS 26 Liquid Glass; the selected tab is a green
// fill inside that capsule (Photos-style), not a second glass layer.
// History + dictionary live as Home cards (not dock tabs).

import SwiftUI
import OSGKeyboardShared

enum AppTab: Int, CaseIterable {
    case keyboard
    case skills
    case styles
    case settings

    var icon: MaterialIconName {
        switch self {
        case .keyboard: return .keyboard
        case .skills, .styles: return .menuBook // unused — these tabs use SF Symbols
        case .settings: return .settings
        }
    }

    /// SF Symbol overrides shared with the Mac and iPad sidebars.
    var sfSymbol: String? {
        switch self {
        case .skills: return "sparkles"
        case .styles: return "text.badge.star"
        default: return nil
        }
    }

    var accessibilityKey: LocalizedStringKey {
        switch self {
        case .keyboard: return "tab.keyboard"
        case .skills: return "tab.skills"
        case .styles: return "tab.styles"
        case .settings: return "tab.settings"
        }
    }

    /// Sidebar label for iPad `NavigationSplitView` (SF Symbol + title).
    var sidebarTitle: LocalizedStringKey { accessibilityKey }

    var sidebarSystemImage: String {
        switch self {
        case .keyboard: return "house"
        case .skills: return "sparkles"
        case .styles: return "text.badge.star"
        case .settings: return "gearshape"
        }
    }
}

struct MinimalTabBar: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectionNamespace
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(Motion.soft) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        Group {
                            if let sfSymbol = tab.sfSymbol {
                                Image(systemName: sfSymbol)
                                    .font(.system(size: TabBarDockMetrics.iconSize, weight: .regular))
                            } else {
                                MaterialIcon(name: tab.icon, size: TabBarDockMetrics.iconSize)
                            }
                        }
                        Text(tab.accessibilityKey)
                            .font(TypeStyle.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(tabIconColor(for: tab))
                    .frame(maxWidth: .infinity)
                    .frame(height: TabBarDockMetrics.itemHeight)
                    .background {
                        if selection == tab {
                            // Stretch into the dock padding so top/bottom
                            // leftover matches the side leftover (~5 pt).
                            Capsule()
                                .fill(palette.accentMuted)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.horizontal, TabBarDockMetrics.selectionInset)
                                .padding(
                                    .vertical,
                                    TabBarDockMetrics.selectionInset
                                        - TabBarDockMetrics.dockInsetVertical
                                )
                                .matchedGeometryEffect(
                                    id: "main-tab-selection",
                                    in: selectionNamespace
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
        .padding(.horizontal, TabBarDockMetrics.dockInsetHorizontal)
        .padding(.vertical, TabBarDockMetrics.dockInsetVertical)
        .glassEffect(.regular.interactive(), in: .capsule)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, TabBarDockMetrics.bottomPadding)
    }

    private func tabIconColor(for tab: AppTab) -> Color {
        if selection == tab { return palette.accent }
        // 未选中：浅色模式更深、深色模式更亮，提升 dock 可读性。
        return colorScheme == .dark
            ? Color(white: 0.76)
            : palette.textSecondary
    }
}
