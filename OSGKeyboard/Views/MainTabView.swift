// MainTabView.swift
// OSGKeyboard · Main App

import OSGKeyboardShared
import SwiftUI

struct MainTabView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var tab: AppTab = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("-osgStartTab=") })?
            .split(separator: "=").last,
           let value = Int(raw),
           let initial = AppTab(rawValue: value)
        {
            return initial
        }
        #endif
        return .keyboard
    }()
    /// Window top safe area; wide pages derive their corner clearance from it.
    /// `nil` until measured, so the first frame does not flash extra padding.
    @State private var topSafeAreaInset: CGFloat?

    private var usesSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            Group {
                if usesSplitLayout {
                    MainSplitView(selection: $tab)
                } else {
                    phoneTabLayout
                }
            }
            .environment(
                \.wideTopCornerClearance,
                topSafeAreaInset.map { WideLayoutMetrics.topCornerClearance(topSafeAreaInset: $0) } ?? 0
            )
        }
        // Fold, rotation and Split View all move the status bar, so track it live.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            topSafeAreaInset = inset
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: .osgOpenSettingsDeepLink)) { _ in
            tab = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .osgOpenAccountDeepLink)) { _ in
            tab = .settings
        }
    }

    // MARK: - Phone layout

    private var phoneTabLayout: some View {
        TabView(selection: $tab) {
            Tab(value: AppTab.keyboard) {
                HomeView()
            } label: {
                tabLabel(for: .keyboard)
            }

            Tab(value: AppTab.skills) {
                AIAgentSkillsView()
            } label: {
                tabLabel(for: .skills)
            }

            Tab(value: AppTab.styles) {
                PolishStylesView()
            } label: {
                tabLabel(for: .styles)
            }

            Tab(value: AppTab.settings) {
                SettingsView(presentation: .tab)
            } label: {
                tabLabel(for: .settings)
            }
        }
        .tint(palette.accent)
        .tabBarMinimizeBehavior(.never)
        // Native TabView owns the floating dock + home-indicator clearance so
        // page footers / scroll ends only need their ordinary bottom spacing.
    }

    private func tabLabel(for item: AppTab) -> some View {
        Label {
            Text(AppL10n.string(item.accessibilityKey))
        } icon: {
            Image(systemName: item.dockSystemImage(selected: tab == item))
        }
        // TabView applies `.fill` to every SF Symbol by default. Opt out so
        // unselected tabs keep their outline while the selected tab uses fill.
        .environment(\.symbolVariants, .none)
    }
}
