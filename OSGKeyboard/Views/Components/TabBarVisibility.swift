// TabBarVisibility.swift
// OSGKeyboard · Main App
//
// Push 进 NavigationStack 子页时隐藏底部系统 tab 栏。
// 子页用 `hidesTabBarWhenPushed()` 声明，根页面保持原生 TabView 导航可见。

import OSGKeyboardShared
import SwiftUI

// MARK: - Modifiers

extension View {
    /// Marks this view as a pushed detail screen so the native tab bar hides.
    func hidesTabBarWhenPushed() -> some View {
        toolbar(.hidden, for: .tabBar)
    }

    /// Adds ordinary footer breathing room; native TabView owns tab-bar clearance.
    func tabBarScrollBottomPadding() -> some View {
        padding(.bottom, Spacing.lg)
    }

    /// Adds a scrollable footer margin to `List` content above the system tab bar.
    func tabBarListScrollBottomMargin() -> some View {
        contentMargins(
            .bottom,
            Spacing.lg,
            for: .scrollContent
        )
    }
}
