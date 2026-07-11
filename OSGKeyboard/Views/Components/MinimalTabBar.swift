// MinimalTabBar.swift
// OSGKeyboard · Main App
//
// Bottom tab bar — four icons, no labels.
// Capsule uses iOS 26 Liquid Glass (.regular.interactive) so content
// behind the dock refracts through on scroll.

import SwiftUI
import OSGKeyboardShared

enum AppTab: Int, CaseIterable {
    case keyboard
    case history
    case dictionary
    case settings

    var icon: MaterialIconName {
        switch self {
        case .keyboard: return .keyboard
        case .history: return .menuBook
        case .dictionary: return .menuBook // unused — dictionary uses SF Symbol
        case .settings: return .settings
        }
    }

    /// Filled SF Symbol override for the dictionary tab.
    var sfSymbol: String? {
        switch self {
        case .dictionary: return "square.stack.3d.down.right.fill"
        default: return nil
        }
    }

    var accessibilityKey: LocalizedStringKey {
        switch self {
        case .keyboard: return "tab.keyboard"
        case .history: return "tab.history"
        case .dictionary: return "tab.dictionary"
        case .settings: return "tab.settings"
        }
    }

    /// Sidebar label for iPad `NavigationSplitView` (SF Symbol + title).
    var sidebarTitle: LocalizedStringKey { accessibilityKey }

    var sidebarSystemImage: String {
        switch self {
        case .keyboard: return "house"
        case .history: return "clock.arrow.circlepath"
        case .dictionary: return "character.book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct MinimalTabBar: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.rawValue) { tab in
                Button {
                    withAnimation(Motion.quick) { selection = tab }
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
        .frame(maxWidth: 336)
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
