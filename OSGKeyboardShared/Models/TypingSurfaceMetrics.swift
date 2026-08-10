// TypingSurfaceMetrics.swift
// OSGKeyboard · Shared
//
// Size decisions for the typing surface: which key metrics apply, and how tall
// the keyboard must be to hold them.
//
// These live here rather than next to the SwiftUI view because two independent
// consumers must agree on them exactly — `KeyboardViewController` sets a UIKit
// height constraint, and the SwiftUI grid lays keys out inside it. If they ever
// pick different metrics the bottom row is clipped, so there is one source of
// truth and it is unit-testable without the extension target.

import CoreGraphics

public enum TypingSurfaceMetrics {
    // MARK: - Structural bands (identical on every device)

    /// Candidate / top control band above the key grid.
    public static let topRegionHeight: CGFloat = 44
    /// Gap between the top band and the first key row.
    public static let verticalKeySpacing: CGFloat = 8
    public static let outerPaddingTop: CGFloat = 4
    public static let outerPaddingBottom: CGFloat = 4

    // MARK: - Phone

    public static let keyRowHeight: CGFloat = 50
    public static let keyRowSpacing: CGFloat = 7
    public static let keyHorizontalSpacing: CGFloat = 6
    public static let secondRowInset: CGFloat = 18

    // MARK: - iPad (narrow: portrait, or a compact-ish regular window)

    public static let iPadKeyRowHeight: CGFloat = 54
    public static let iPadKeyRowSpacing: CGFloat = 8
    public static let iPadKeyHorizontalSpacing: CGFloat = 8

    // MARK: - iPad (wide: landscape or a large Stage Manager window)

    /// The grid spans the full host width here, so rows must grow with it.
    /// Holding the narrow 54 pt height at ~1200 pt wide produces 110×54 keys —
    /// flatter than any system key.
    public static let wideIPadKeyRowHeight: CGFloat = 76
    public static let wideIPadKeyRowSpacing: CGFloat = 10
    public static let wideIPadKeyHorizontalSpacing: CGFloat = 10

    /// Key metrics for a device class and available width. Width — not device
    /// orientation — picks the wide bucket, so a resized Stage Manager window
    /// lands on the right metrics without consulting orientation at all.
    public static func metrics(isIPad: Bool, width: CGFloat) -> TypingKeyLayoutBuilder.Metrics {
        guard isIPad else {
            return TypingKeyLayoutBuilder.Metrics(
                keyRowHeight: keyRowHeight,
                keyRowSpacing: keyRowSpacing,
                keyHorizontalSpacing: keyHorizontalSpacing,
                secondRowInset: secondRowInset,
                bottomRowHeight: KeyboardChromeLayout.actionKeyHeight,
                bottomActionSpacing: KeyboardChromeLayout.actionKeySpacing,
                gridToBottomSpacing: keyRowSpacing
            )
        }
        let isWide = KeyboardChromeLayout.usesWideIPadMetrics(isIPad: true, width: width)
        let rowHeight = isWide ? wideIPadKeyRowHeight : iPadKeyRowHeight
        let rowSpacing = isWide ? wideIPadKeyRowSpacing : iPadKeyRowSpacing
        return TypingKeyLayoutBuilder.Metrics(
            keyRowHeight: rowHeight,
            keyRowSpacing: rowSpacing,
            keyHorizontalSpacing: isWide ? wideIPadKeyHorizontalSpacing : iPadKeyHorizontalSpacing,
            // Ignored: iPad derives the indent from the first row's key width.
            secondRowInset: 0,
            bottomRowHeight: rowHeight,
            bottomActionSpacing: KeyboardChromeLayout.actionKeySpacing,
            gridToBottomSpacing: rowSpacing,
            derivesSecondRowInsetFromKeyWidth: true
        )
    }

    /// Content-driven keyboard height. iPad grows its rows, so the shell has to
    /// grow with them or the bottom row is clipped.
    public static func contentHeight(isIPad: Bool, width: CGFloat) -> CGFloat {
        guard isIPad else { return KeyboardChromeLayout.totalHeight }
        let m = metrics(isIPad: true, width: width)
        let inner = topRegionHeight
            + verticalKeySpacing
            + (3 * m.keyRowHeight + 2 * m.keyRowSpacing)
            + m.gridToBottomSpacing
            + m.bottomRowHeight
        return inner + outerPaddingTop + outerPaddingBottom
    }
}
