// PrivacyDisclosureViews.swift
// OSGKeyboard · Main App
//
// Reusable privacy / data-flow disclosure blocks for Settings and Onboarding.

import SwiftUI
import OSGKeyboardShared

/// Card-style block for Full Access and similar permission explanations.
struct PrivacyInfoCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: LocalizedStringKey
    let bodyText: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Text(bodyText)
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.large, style: .continuous)
                .stroke(palette.divider, lineWidth: 0.5)
        )
    }
}

/// Footnote when Cloud polish is active — text goes to the user's configured API.
struct CloudPolishDisclosureBanner: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accent)
            Text("settings.privacy.cloud.body")
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.accentMuted.opacity(0.35), in: RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
    }
}

/// First-time confirmation before enabling Cloud polish (user-configured third-party API).
struct CloudSharingAcknowledgmentModifier: ViewModifier {
    @ObservedObject var config: ProviderConfig
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("settings.privacy.cloud.alert.title", isPresented: $isPresented) {
                Button("common.continue") {
                    config.hasAcknowledgedCloudSharing = true
                    onConfirm()
                }
                Button("common.cancel", role: .cancel) {
                    onCancel()
                }
            } message: {
                Text("settings.privacy.cloud.alert.message")
            }
    }
}

extension View {
    func cloudSharingAcknowledgment(
        config: ProviderConfig,
        isPresented: Binding<Bool>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(CloudSharingAcknowledgmentModifier(
            config: config,
            isPresented: isPresented,
            onConfirm: onConfirm,
            onCancel: onCancel
        ))
    }
}
