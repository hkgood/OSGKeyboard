// MainTabView.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct MainTabView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var flowManager: FlowSessionManager

    @State private var tab: AppTab = .keyboard
    @State private var isTabBarHidden = false

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
    }

    // MARK: - Phone layout

    private var phoneTabLayout: some View {
        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()

            MainTabContent(tab: tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.isTabBarVisible, !isTabBarHidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isTabBarHidden {
                        // Match floating dock + home-indicator clearance so
                        // page footers / scroll ends sit above MinimalTabBar.
                        Color.clear.frame(height: 100)
                    }
                }
                .onPreferenceChange(TabBarHiddenPreferenceKey.self) { hidden in
                    withAnimation(Motion.quick) {
                        isTabBarHidden = hidden
                    }
                }

            if !isTabBarHidden {
                MinimalTabBar(selection: $tab)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
