// MainTabView.swift
// OSGKeyboard · Main App

import SwiftUI
import OSGKeyboardShared

struct MainTabView: View {
    @Environment(\.themePalette) private var palette: ThemePalette
    @EnvironmentObject private var flowManager: FlowSessionManager

    @State private var tab: AppTab = .keyboard

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()

            Group {
                switch tab {
                case .keyboard:
                    HomeView()
                case .history:
                    HistoryView()
                case .settings:
                    SettingsView(presentation: .tab)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 88)
            }

            MinimalTabBar(selection: $tab)
        }
        .onAppear { flowManager.autoStartIfNeeded() }
    }
}
