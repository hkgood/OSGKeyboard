// KeyboardChromeLayout.swift
// OSGKeyboard · Shared
//
// Cross-surface dimensions that must stay identical in voice and typing modes.

import CoreGraphics

public enum KeyboardChromeLayout {
    public static let totalHeight: CGFloat = 281
    public static let actionKeyHeight: CGFloat = 50
    public static let actionKeyCornerRadius: CGFloat = 10
    /// Shared geometry for every three-key bottom row.
    public static let actionKeySpacing: CGFloat = 8
    public static let sideActionKeyFraction: CGFloat = 0.2
    public static let centerActionKeyFraction: CGFloat = 0.6
    public static let horizontalInset: CGFloat = 8
    /// Keeps voice and typing controls equally reachable on iPad.
    public static let contentMaxWidth: CGFloat = 700

    /// Splits the width left after spacing into a 20 / 60 / 20 row.
    public static func actionKeyWidths(availableWidth: CGFloat) -> (side: CGFloat, center: CGFloat) {
        let keyWidth = max(0, availableWidth - actionKeySpacing * 2)
        return (
            side: keyWidth * sideActionKeyFraction,
            center: keyWidth * centerActionKeyFraction
        )
    }
}
