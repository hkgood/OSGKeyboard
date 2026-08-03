// KeyboardChromeLayout.swift
// OSGKeyboard · Shared
//
// Cross-surface dimensions that must stay identical in voice and typing modes.

import CoreGraphics

public enum KeyboardChromeLayout {
    public static let totalHeight: CGFloat = 281
    public static let actionKeyHeight: CGFloat = 50
    public static let actionKeyCornerRadius: CGFloat = 10
    /// Fixed width for the two side keys in every three-key bottom row.
    public static let sideActionKeyWidth: CGFloat = 86
    public static let horizontalInset: CGFloat = 8
}
