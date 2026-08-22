// MainTabView.swift
// OSGKeyboard · Main App

import OSGKeyboardShared
import SwiftUI

struct MainTabView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var tab: AppTab = .keyboard

    private var usesSplitLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                MainSplitView(selection: $tab)
            } else {
                phoneTabLayout
            }
        }
        .background(palette.background)
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
            Text(item.accessibilityKey)
        } icon: {
            Image(systemName: item.dockSystemImage(selected: tab == item))
        }
        // TabView applies `.fill` to every SF Symbol by default. Opt out so
        // unselected tabs keep their outline while the selected tab uses fill.
        .environment(\.symbolVariants, .none)
    }
}
