// AppTab.swift
// OSGKeyboard · Main App
//
// Shared top-level destinations for the native iPhone TabView and iPad sidebar.

import SwiftUI

enum AppTab: Int, CaseIterable {
    case keyboard
    case skills
    case styles
    case settings

    var accessibilityKey: LocalizedStringKey {
        switch self {
        case .keyboard: return "tab.keyboard"
        case .skills: return "tab.skills"
        case .styles: return "tab.styles"
        case .settings: return "tab.settings"
        }
    }

    /// Native phone tab symbol: outline when idle, fill when selected.
    /// `wand.and.sparkles` has no `.fill` pair.
    func dockSystemImage(selected: Bool) -> String {
        switch self {
        case .keyboard: return selected ? "keyboard.fill" : "keyboard"
        case .skills: return "wand.and.sparkles"
        case .styles: return selected ? "dial.high.fill" : "dial.high"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        }
    }

    /// Sidebar label for iPad `NavigationSplitView` (SF Symbol + title).
    var sidebarTitle: LocalizedStringKey { accessibilityKey }

    /// iPad sidebar. Home stays `house` in both states; other tabs follow
    /// the same outline / fill pairing as the phone tab bar.
    func sidebarSystemImage(selected: Bool) -> String {
        switch self {
        case .keyboard: return "house"
        case .skills: return "wand.and.sparkles"
        case .styles: return selected ? "dial.high.fill" : "dial.high"
        case .settings: return selected ? "gearshape.fill" : "gearshape"
        }
    }
}
