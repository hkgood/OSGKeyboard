// MainTabView.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct MainTabView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @EnvironmentObject private var flowManager: FlowSessionManager

    @State private var tab: AppTab = .keyboard
    @State private var isTabBarHidden = false

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()

            Group {
                switch tab {
                case .keyboard:
                    HomeView()
                case .history:
                    HistoryView()
                case .dictionary:
                    PersonalDictionaryView()
                case .settings:
                    SettingsView(presentation: .tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.isTabBarVisible, !isTabBarHidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isTabBarHidden {
                    Color.clear.frame(height: 88)
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
        // Keep home card/input/tab layout fixed when system keyboard appears.
        // Let the keyboard overlay the content instead of pushing it.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}
