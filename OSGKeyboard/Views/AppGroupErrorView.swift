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
            Text("appGroup.error.title")
                .font(TypeStyle.title2)
                .multilineTextAlignment(.center)
            Text("appGroup.error.body")
                .font(TypeStyle.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textSecondary)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("appGroup.error.step1", systemImage: "1.circle")
                Label("appGroup.error.step2", systemImage: "2.circle")
                Label("appGroup.error.step3", systemImage: "3.circle")
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
