// AppGroupErrorView.swift
// OSGKeyboard · Main App
//
// Shown in place of the normal Home/Onboarding flow when the App Group
// container is not configured. The whole app is unusable without it (the
// keyboard extension and the main app cannot share state), so we don't
// try to be clever — we show a clear, actionable error and stop.
//
// We deliberately do NOT fatalError in release: the developer might be
// running a TestFlight build with a stripped entitlement, and a friendly
// screen is much better than a crash loop.

import SwiftUI
import OSGKeyboardShared

struct AppGroupErrorView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(palette.danger)
            Text("App Group 未配置")
                .font(TypeStyle.title2)
            Text("OSGKeyboard 需要 App Group 才能在键盘扩展和主 App 之间共享配置。")
                .font(TypeStyle.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("在 Apple Developer 后台创建 group.com.osgkeyboard.shared", systemImage: "1.circle")
                Label("主 App 和键盘扩展都启用该 App Group", systemImage: "2.circle")
                Label("重新生成 provisioning profile 并下载", systemImage: "3.circle")
            }
            .font(TypeStyle.body)
            .foregroundStyle(palette.textPrimary)
        }
        .padding(Spacing.lg)
    }
}

#if DEBUG
#Preview {
    ThemedRoot {
        AppGroupErrorView()
    }
}
#endif
