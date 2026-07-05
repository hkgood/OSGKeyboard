// TabBarVisibility.swift
// OSGKeyboard · Main App
//
// Push 进 NavigationStack 子页时隐藏底部自定义 tab 栏（对齐系统 TabView 行为）。
// MainTabView 读取 `TabBarHiddenPreferenceKey`；子页用 `hidesTabBarWhenPushed()` 声明。

import SwiftUI
import OSGKeyboardShared

// MARK: - Preference

enum TabBarHiddenPreferenceKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Environment

private enum TabBarVisibleEnvironmentKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// `false` when the custom dock is hidden (detail push / sheet over tab content).
    var isTabBarVisible: Bool {
        get { self[TabBarVisibleEnvironmentKey.self] }
        set { self[TabBarVisibleEnvironmentKey.self] = newValue }
    }
}

// MARK: - Modifiers

extension View {
    /// Marks this view as a pushed detail screen so `MainTabView` hides the dock.
    func hidesTabBarWhenPushed() -> some View {
        preference(key: TabBarHiddenPreferenceKey.self, value: true)
    }

    /// Bottom inset for scroll content above the floating dock (tab root pages only).
    func tabBarScrollBottomPadding() -> some View {
        modifier(TabBarScrollBottomPaddingModifier())
    }
}

private struct TabBarScrollBottomPaddingModifier: ViewModifier {
    @Environment(\.isTabBarVisible) private var isTabBarVisible

    private let dockClearance: CGFloat = 100

    func body(content: Content) -> some View {
        content.padding(.bottom, isTabBarVisible ? dockClearance : Spacing.lg)
    }
}
