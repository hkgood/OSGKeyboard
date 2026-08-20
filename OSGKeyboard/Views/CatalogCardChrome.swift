// CatalogCardChrome.swift
// OSGKeyboard · Main App
//
// Shared edit / selected badges for style and skill cards.

import OSGKeyboardShared
import SwiftUI

enum CatalogCardChrome {
    static let badgeSize: CGFloat = 30
    static let editIconSize: CGFloat = 15
    static let checkIconSize: CGFloat = 21
    static let editHitSize: CGFloat = 44

    static func editIcon(palette: ThemePalette) -> some View {
        Image(systemName: "pencil")
            .font(.system(size: editIconSize, weight: .semibold))
            .foregroundStyle(palette.textSecondary)
            .frame(width: badgeSize, height: badgeSize)
            .background(palette.background.opacity(0.75), in: Circle())
    }

    static func checkIcon(palette: ThemePalette) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: checkIconSize, weight: .semibold))
            .foregroundStyle(palette.accent)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .allowsHitTesting(false)
    }
}
