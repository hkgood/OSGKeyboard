// KeyHitTesting.swift
// OSGKeyboard · Shared
//
// Pure geometry for typing-key hit testing: invisible gap fill, edge
// expansion, and a light upward intent offset (Phase 1 + Phase 3).

import CoreGraphics
import Foundation

/// How a key should respond once the finger is tracked onto it.
public enum TypingKeyTouchBehavior: Equatable, Sendable {
    /// Highlight on down / move; commit on finger-up (letters, space, return…).
    case commitOnRelease
    /// Fire on down and repeat while held (delete).
    case deleteRepeat
    /// Hold-to-shift while the gesture owns Shift (⇧).
    case shiftHold
}

/// One hittable key in surface coordinates.
public struct TypingKeyHitTarget: Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let visualFrame: CGRect
    public let behavior: TypingKeyTouchBehavior

    public init(
        id: String,
        label: String,
        visualFrame: CGRect,
        behavior: TypingKeyTouchBehavior
    ) {
        self.id = id
        self.label = label
        self.visualFrame = visualFrame
        self.behavior = behavior
    }

    public var center: CGPoint {
        CGPoint(x: visualFrame.midX, y: visualFrame.midY)
    }
}

/// Tunables for gap-filling hit regions and finger intent correction.
public enum KeyHitTestingMetrics: Sendable {
    /// Shift the reported touch slightly upward — thumbs contact below the
    /// visual aim point.
    public static let intentOffsetY: CGFloat = 4
    /// Extra expansion on the outer edges of the key plane (Q / P / …).
    public static let edgeExpansion: CGFloat = 5
}

public enum KeyHitTesting {
    /// Map a raw touch into an intent point (Phase 3).
    public static func intentPoint(
        from point: CGPoint,
        offsetY: CGFloat = KeyHitTestingMetrics.intentOffsetY
    ) -> CGPoint {
        CGPoint(x: point.x, y: point.y - offsetY)
    }

    /// Expand a visual key frame so neighboring keys meet at the mid-gap
    /// (no dead zone). Outer keys grow further past the plane edge.
    public static func expandedHitFrame(
        for visualFrame: CGRect,
        keyPlaneBounds: CGRect,
        horizontalGap: CGFloat,
        verticalGap: CGFloat,
        edgeExpansion: CGFloat = KeyHitTestingMetrics.edgeExpansion
    ) -> CGRect {
        var frame = visualFrame.insetBy(
            dx: -horizontalGap / 2,
            dy: -verticalGap / 2
        )

        let epsilon: CGFloat = 0.5
        if visualFrame.minX <= keyPlaneBounds.minX + epsilon {
            frame.origin.x -= edgeExpansion
            frame.size.width += edgeExpansion
        }
        if visualFrame.maxX >= keyPlaneBounds.maxX - epsilon {
            frame.size.width += edgeExpansion
        }
        if visualFrame.minY <= keyPlaneBounds.minY + epsilon {
            frame.origin.y -= edgeExpansion
            frame.size.height += edgeExpansion
        }
        if visualFrame.maxY >= keyPlaneBounds.maxY - epsilon {
            frame.size.height += edgeExpansion
        }
        return frame
    }

    /// Resolve which key owns `point` (already intent-corrected, or raw).
    ///
    /// - Returns `nil` when the point is outside the key plane (cancel).
    /// - Inside the plane: prefer expanded frames; fall back to nearest center
    ///   so mid-gap touches never miss.
    public static func hitTarget(
        at point: CGPoint,
        targets: [TypingKeyHitTarget],
        keyPlaneBounds: CGRect,
        horizontalGap: CGFloat,
        verticalGap: CGFloat,
        edgeExpansion: CGFloat = KeyHitTestingMetrics.edgeExpansion,
        hitWeights: [String: CGFloat] = [:]
    ) -> TypingKeyHitTarget? {
        guard !targets.isEmpty else { return nil }

        let activePlane = keyPlaneBounds.insetBy(
            dx: -edgeExpansion,
            dy: -edgeExpansion
        )
        guard activePlane.contains(point) else { return nil }

        let expanded = targets.map { target in
            (
                target,
                expandedHitFrame(
                    for: target.visualFrame,
                    keyPlaneBounds: keyPlaneBounds,
                    horizontalGap: horizontalGap,
                    verticalGap: verticalGap,
                    edgeExpansion: edgeExpansion
                )
            )
        }

        let containing = expanded.compactMap { target, frame -> TypingKeyHitTarget? in
            frame.contains(point) ? target : nil
        }

        // Clear single-key hit always wins — bias only breaks ties / nearest.
        if containing.count == 1 {
            return containing[0]
        }
        if containing.count > 1 {
            return nearest(to: point, among: containing, hitWeights: hitWeights)
        }
        return nearest(to: point, among: targets, hitWeights: hitWeights)
    }

    /// Convenience: apply intent offset then hit-test.
    public static func hitTarget(
        rawTouch point: CGPoint,
        targets: [TypingKeyHitTarget],
        keyPlaneBounds: CGRect,
        horizontalGap: CGFloat,
        verticalGap: CGFloat,
        intentOffsetY: CGFloat = KeyHitTestingMetrics.intentOffsetY,
        edgeExpansion: CGFloat = KeyHitTestingMetrics.edgeExpansion,
        hitWeights: [String: CGFloat] = [:]
    ) -> TypingKeyHitTarget? {
        hitTarget(
            at: intentPoint(from: point, offsetY: intentOffsetY),
            targets: targets,
            keyPlaneBounds: keyPlaneBounds,
            horizontalGap: horizontalGap,
            verticalGap: verticalGap,
            edgeExpansion: edgeExpansion,
            hitWeights: hitWeights
        )
    }

    private static func nearest(
        to point: CGPoint,
        among targets: [TypingKeyHitTarget],
        hitWeights: [String: CGFloat]
    ) -> TypingKeyHitTarget? {
        targets.min { lhs, rhs in
            weightedDistanceSquared(point, lhs, hitWeights)
                < weightedDistanceSquared(point, rhs, hitWeights)
        }
    }

    private static func weightedDistanceSquared(
        _ point: CGPoint,
        _ target: TypingKeyHitTarget,
        _ hitWeights: [String: CGFloat]
    ) -> CGFloat {
        let weight = max(0.01, hitWeights[target.id] ?? 1.0)
        return distanceSquared(point, target.center) / weight
    }

    private static func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

/// Resolve touch behavior from a visible key label.
public enum TypingKeyBehaviorResolver {
    public static func behavior(for label: String) -> TypingKeyTouchBehavior {
        switch label {
        case "⌫":
            return .deleteRepeat
        case "⇧":
            return .shiftHold
        default:
            return .commitOnRelease
        }
    }
}
