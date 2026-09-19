// PrivacyDisclosureViews.swift
// OSGKeyboard · Main App
//
// Reusable privacy / data-flow disclosure blocks for Settings and Onboarding.

import OSGKeyboardShared
import SwiftUI

/// Card-style block for Full Access and similar permission explanations.
struct PrivacyInfoCard: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(AppL10n.string(title))
                .font(TypeStyle.body)
                .foregroundStyle(palette.textPrimary)
            Text(AppL10n.string(bodyText))
                .font(TypeStyle.caption2)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.large, style: .continuous))
        .cardElevation()
    }
}
