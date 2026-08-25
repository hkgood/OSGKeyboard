// TabBarVisibility.swift
// OSGKeyboard · Main App
//
// NavigationStack 根路径统一驱动底部系统 tab 栏显隐。
// 显隐状态在 push / pop 开始时更新，使原生 Dock 与页面过渡同步。

import OSGKeyboardShared
import SwiftUI

// MARK: - Modifiers

private struct NavigationStackTabBarVisibilityModifier: ViewModifier {
    let isRoot: Bool

    @State private var visibility: Visibility = .visible

    func body(content: Content) -> some View {
        content
            .toolbarVisibility(visibility, for: .tabBar)
            .onAppear {
                visibility = isRoot ? .visible : .hidden
            }
            .onChange(of: isRoot) { _, newValue in
                withAnimation(Motion.soft) {
                    visibility = newValue ? .visible : .hidden
                }
            }
    }
}

extension View {
    /// Keeps the native tab dock visible only at a NavigationStack root.
    func navigationStackTabBarVisibility(isRoot: Bool) -> some View {
        modifier(NavigationStackTabBarVisibilityModifier(isRoot: isRoot))
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
