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
        /// When true, `secondRowInset` is ignored and the second row is inset
        /// so its keys are exactly as wide as the first row's, leaving a half
        /// key at each end — what the system keyboard does. A fixed inset is a
        /// fraction of a 700 pt column and stops reading as a deliberate
        /// indent once the grid fills an iPad's width.
        public var derivesSecondRowInsetFromKeyWidth: Bool

        public init(
            keyRowHeight: CGFloat = 50,
            keyRowSpacing: CGFloat = 7,
            keyHorizontalSpacing: CGFloat = 6,
            secondRowInset: CGFloat = 18,
            bottomRowHeight: CGFloat = KeyboardChromeLayout.actionKeyHeight,
            bottomActionSpacing: CGFloat = KeyboardChromeLayout.actionKeySpacing,
            gridToBottomSpacing: CGFloat = 7,
            derivesSecondRowInsetFromKeyWidth: Bool = false
        ) {
            self.keyRowHeight = keyRowHeight
            self.keyRowSpacing = keyRowSpacing
            self.keyHorizontalSpacing = keyHorizontalSpacing
            self.secondRowInset = secondRowInset
            self.bottomRowHeight = bottomRowHeight
            self.bottomActionSpacing = bottomActionSpacing
            self.gridToBottomSpacing = gridToBottomSpacing
            self.derivesSecondRowInsetFromKeyWidth = derivesSecondRowInsetFromKeyWidth
        }
    }

    /// Inset that makes `row` keys as wide as a full `referenceCount` row.
    /// Both rows are laid out at the same unit width, so the second row simply
    /// gives back the width of the keys it does not have, split evenly.
    static func derivedSecondRowInset(
        totalWidth: CGFloat,
        referenceCount: Int,
        rowCount: Int,
        spacing: CGFloat,
        weightTotal: CGFloat,
        referenceWeightTotal: CGFloat
    ) -> CGFloat {
        guard referenceCount > 0, rowCount > 0, referenceWeightTotal > 0 else { return 0 }
        let referenceSpacing = spacing * CGFloat(max(0, referenceCount - 1))
        let unitWidth = (totalWidth - referenceSpacing) / referenceWeightTotal
        let rowWidth = unitWidth * weightTotal + spacing * CGFloat(max(0, rowCount - 1))
        return max(0, (totalWidth - rowWidth) / 2)
    }

    /// Bottom-row semantic labels used by the touch pad (not always the glyph).
    /// When present on iPad, the globe key is excluded from the touch pad's hit
    /// testing — its `SystemGlobeKey` UIButton handles tap (advance) /
    /// long-press (system input-mode list) directly.
    public enum BottomKeyID: String, Sendable {
        case globe = "bottom.globe"
        case pageSwitch = "bottom.page"
        case comma = "bottom.comma"
        case space = "bottom.space"
        case period = "bottom.period"
        case `return` = "bottom.return"
    }

    /// Comma / period glyphs for the iPad bottom row. `nil` keeps the phone's
    /// four-slot row.
    public struct PunctuationKeys: Equatable, Sendable {
        public let comma: String
        public let period: String

        public init(comma: String, period: String) {
            self.comma = comma
            self.period = period
        }
    }

    public static func build(
        size: CGSize,
        letterRows: [[String]],
        pageSwitchLabel: String,
        spaceLabel: String,
        returnLabel: String,
        metrics: Metrics = Metrics(),
        includeGlobeKey: Bool = true,
        punctuationKeys: PunctuationKeys? = nil,
        showTopRowNumbers: Bool = false,
        topRowNumbers: [String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        keyWeight: (_ label: String, _ index: Int, _ rowIndex: Int) -> CGFloat
    ) -> TypingKeyLayout {
        var keys: [TypingKeyHitTarget] = []
        var cursorY: CGFloat = 0

        let firstRow = letterRows.first ?? []
        let firstRowWeightTotal = firstRow.enumerated()
            .map { keyWeight($0.element, $0.offset, 0) }
            .reduce(0, +)

        for (rowIndex, row) in letterRows.enumerated() {
            let weights = row.enumerated().map { keyWeight($0.element, $0.offset, rowIndex) }
            let inset: CGFloat
            if rowIndex == 1 {
                inset = metrics.derivesSecondRowInsetFromKeyWidth
                    ? derivedSecondRowInset(
                        totalWidth: size.width,
                        referenceCount: firstRow.count,
                        rowCount: row.count,
                        spacing: metrics.keyHorizontalSpacing,
                        weightTotal: weights.reduce(0, +),
                        referenceWeightTotal: firstRowWeightTotal
                    )
                    : metrics.secondRowInset
            } else {
                inset = 0
            }
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
                // iPad top letter row carries the small number overlay (1–0),
                // mirroring the iOS system keyboard. Interior rows don't.
                let number = (showTopRowNumbers
                    && rowIndex == 0
                    && keyIndex < topRowNumbers.count)
                    ? topRowNumbers[keyIndex]
                    : nil
                keys.append(
                    TypingKeyHitTarget(
                        id: "grid.\(rowIndex).\(keyIndex)",
                        label: label,
                        visualFrame: frame,
                        behavior: TypingKeyBehaviorResolver.behavior(for: label),
                        displayNumber: number
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
        // On iPad the globe lives at the far-left as a UIKit-backed key
        // (handled by SystemGlobeKey); registering its frame reserves the slot
        // and lets the touch pad skip hit-testing it. iPhone omits the slot.
        let bottomFrames: [(String, String, CGFloat)]
        if let punctuationKeys {
            let widths = KeyboardChromeLayout.iPadActionKeyWidths(availableWidth: size.width)
            bottomFrames = [
                (BottomKeyID.globe.rawValue, "", widths.globe),
                (BottomKeyID.pageSwitch.rawValue, pageSwitchLabel, widths.pageSwitch),
                (BottomKeyID.comma.rawValue, punctuationKeys.comma, widths.comma),
                (BottomKeyID.space.rawValue, spaceLabel, widths.space),
                (BottomKeyID.period.rawValue, punctuationKeys.period, widths.period),
                (BottomKeyID.return.rawValue, returnLabel, widths.return)
            ]
        } else if includeGlobeKey {
            let widths = KeyboardChromeLayout.actionKeyWidths(availableWidth: size.width)
            bottomFrames = [
                (BottomKeyID.globe.rawValue, "", widths.globe),
                (BottomKeyID.pageSwitch.rawValue, pageSwitchLabel, widths.side),
                (BottomKeyID.space.rawValue, spaceLabel, widths.center),
                (BottomKeyID.return.rawValue, returnLabel, widths.side2)
            ]
        } else {
            let widths = KeyboardChromeLayout.actionKeyWidthsWithoutGlobe(
                availableWidth: size.width
            )
            bottomFrames = [
                (BottomKeyID.pageSwitch.rawValue, pageSwitchLabel, widths.side),
                (BottomKeyID.space.rawValue, spaceLabel, widths.center),
                (BottomKeyID.return.rawValue, returnLabel, widths.side2)
            ]
        }

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
