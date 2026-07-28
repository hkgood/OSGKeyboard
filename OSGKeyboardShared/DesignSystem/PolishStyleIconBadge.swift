// PolishStyleIconBadge.swift
// OSGKeyboard · Shared
//
// Circular SF Symbol badge for polish-style cards. Fixed footprint keeps icons
// visually consistent across built-in and user-defined styles on iOS and macOS.

import SwiftUI

public struct PolishStyleIconBadge: View {
    @Environment(\.themePalette) private var palette

    public let systemImage: String
    public var isSelected: Bool

    private let circleSize: CGFloat = 40
    private let iconSize: CGFloat = 18

    public init(pack: PolishStylePack, isSelected: Bool = false) {
        self.systemImage = PolishStylePackCatalog.systemImage(for: pack.id)
        self.isSelected = isSelected
    }

    public init(systemImage: String, isSelected: Bool = false) {
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? palette.accentMuted : palette.surfaceMuted)
                .frame(width: circleSize, height: circleSize)
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(isSelected ? palette.accent : palette.textSecondary)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: circleSize, height: circleSize)
        .accessibilityHidden(true)
    }
}
