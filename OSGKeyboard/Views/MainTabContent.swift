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
        case .history:
            HistoryView()
        case .dictionary:
            PersonalDictionaryView()
        case .settings:
            SettingsView(presentation: .tab)
        }
    }
}
