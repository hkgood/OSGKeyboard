// MainTabContent.swift
// OSGKeyboard · Main App
//
// Shared tab destination switcher used by both the phone dock and the iPad
// split-view detail column.

import SwiftUI
import OSGKeyboardShared

struct MainTabContent: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .keyboard:
            HomeView()
        case .skills:
            AIAgentSkillsView()
        case .styles:
            PolishStylesView()
        case .settings:
            SettingsView(presentation: .tab)
        }
    }
}
