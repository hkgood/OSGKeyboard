// TypingKeyLayout.swift
// OSGKeyboard · Shared
//
// Builds visual frames for the typing grid + bottom action row so hit
// testing and rendering share one geometry source.

import CoreGraphics
import Foundation

public struct TypingKeyLayout: Equatable, Sendable {
    public let keys: [TypingKeyHitTarget]
    /// Union of all visual key frames (letter grid + bottom row).
    public let keyPlaneBounds: CGRect
    public let horizontalGap: CGFloat
    public let verticalGap: CGFloat
    public let bottomRowMinY: CGFloat
    /// Phase 4: per-key hit weights for ambiguous nearest resolution.
    /// Empty / missing id → neutral (`1.0`).
    public let hitWeights: [String: CGFloat]

    public init(
        keys: [TypingKeyHitTarget],
        keyPlaneBounds: CGRect,
        horizontalGap: CGFloat,
        verticalGap: CGFloat,
        bottomRowMinY: CGFloat,
        hitWeights: [String: CGFloat] = [:]
    ) {
        self.keys = keys
        self.keyPlaneBounds = keyPlaneBounds
        self.horizontalGap = horizontalGap
        self.verticalGap = verticalGap
        self.bottomRowMinY = bottomRowMinY
        self.hitWeights = hitWeights
    }

    public func key(id: String) -> TypingKeyHitTarget? {
        keys.first { $0.id == id }
    }

    public func withHitWeights(_ weights: [String: CGFloat]) -> TypingKeyLayout {
        TypingKeyLayout(
            keys: keys,
            keyPlaneBounds: keyPlaneBounds,
            horizontalGap: horizontalGap,
            verticalGap: verticalGap,
            bottomRowMinY: bottomRowMinY,
            hitWeights: weights
        )
    }
}

public enum TypingKeyLayoutBuilder {
    public struct Metrics: Equatable, Sendable {
        public var keyRowHeight: CGFloat
        public var keyRowSpacing: CGFloat
        public var keyHorizontalSpacing: CGFloat
        public var secondRowInset: CGFloat
        public var bottomRowHeight: CGFloat
        public var bottomActionSpacing: CGFloat
        /// Gap between the last letter row and the bottom action row.
        public var gridToBottomSpacing: CGFloat

        public init(
            keyRowHeight: CGFloat = 50,
            keyRowSpacing: CGFloat = 7,
            keyHorizontalSpacing: CGFloat = 6,
            secondRowInset: CGFloat = 18,
            bottomRowHeight: CGFloat = KeyboardChromeLayout.actionKeyHeight,
            bottomActionSpacing: CGFloat = KeyboardChromeLayout.actionKeySpacing,
            gridToBottomSpacing: CGFloat = 7
        ) {
            self.keyRowHeight = keyRowHeight
            self.keyRowSpacing = keyRowSpacing
            self.keyHorizontalSpacing = keyHorizontalSpacing
            self.secondRowInset = secondRowInset
            self.bottomRowHeight = bottomRowHeight
            self.bottomActionSpacing = bottomActionSpacing
            self.gridToBottomSpacing = gridToBottomSpacing
        }
    }

    /// Bottom-row semantic labels used by the touch pad (not always the glyph).
    public enum BottomKeyID: String, Sendable {
        case pageSwitch = "bottom.page"
        case space = "bottom.space"
        case `return` = "bottom.return"
    }

    public static func build(
        size: CGSize,
        letterRows: [[String]],
        pageSwitchLabel: String,
        spaceLabel: String,
        returnLabel: String,
        metrics: Metrics = Metrics(),
        keyWeight: (_ label: String, _ index: Int, _ rowIndex: Int) -> CGFloat
    ) -> TypingKeyLayout {
        var keys: [TypingKeyHitTarget] = []
        var cursorY: CGFloat = 0

        for (rowIndex, row) in letterRows.enumerated() {
            let inset = rowIndex == 1 ? metrics.secondRowInset : 0
            let weights = row.enumerated().map { keyWeight($0.element, $0.offset, rowIndex) }
            let spacingTotal = metrics.keyHorizontalSpacing * CGFloat(max(0, row.count - 1))
            let availableWidth = size.width - inset * 2 - spacingTotal
            let unitWidth = availableWidth / max(1, weights.reduce(0, +))

            var x = inset
            for (keyIndex, label) in row.enumerated() {
                let width = unitWidth * weights[keyIndex]
                let frame = CGRect(
                    x: x,
                    y: cursorY,
                    width: width,
                    height: metrics.keyRowHeight
                )
                keys.append(
                    TypingKeyHitTarget(
                        id: "grid.\(rowIndex).\(keyIndex)",
                        label: label,
                        visualFrame: frame,
                        behavior: TypingKeyBehaviorResolver.behavior(for: label)
                    )
                )
                x += width + metrics.keyHorizontalSpacing
            }

            cursorY += metrics.keyRowHeight
            if rowIndex < letterRows.count - 1 {
                cursorY += metrics.keyRowSpacing
            }
        }

        cursorY += metrics.gridToBottomSpacing
        let bottomY = cursorY
        let widths = KeyboardChromeLayout.actionKeyWidths(availableWidth: size.width)
        let bottomFrames: [(String, String, CGFloat)] = [
            (BottomKeyID.pageSwitch.rawValue, pageSwitchLabel, widths.side),
            (BottomKeyID.space.rawValue, spaceLabel, widths.center),
            (BottomKeyID.return.rawValue, returnLabel, widths.side)
        ]

        var bottomX: CGFloat = 0
        for (index, item) in bottomFrames.enumerated() {
            let frame = CGRect(
                x: bottomX,
                y: bottomY,
                width: item.2,
                height: metrics.bottomRowHeight
            )
            keys.append(
                TypingKeyHitTarget(
                    id: item.0,
                    label: item.1,
                    visualFrame: frame,
                    behavior: .commitOnRelease
                )
            )
            bottomX += item.2
            if index < bottomFrames.count - 1 {
                bottomX += metrics.bottomActionSpacing
            }
        }

        let plane = keys.reduce(CGRect.null) { $0.union($1.visualFrame) }
        return TypingKeyLayout(
            keys: keys,
            keyPlaneBounds: plane.isNull ? .zero : plane,
            horizontalGap: metrics.keyHorizontalSpacing,
            // Between letter rows use keyRowSpacing; between grid and bottom
            // use gridToBottomSpacing. Hit-test uses the larger gap so the
            // mid-gap is always covered.
            verticalGap: max(metrics.keyRowSpacing, metrics.gridToBottomSpacing),
            bottomRowMinY: bottomY
        )
    }
}
