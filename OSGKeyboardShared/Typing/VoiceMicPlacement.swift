// VoiceMicPlacement.swift
// OSGKeyboard · Shared
//
// Vertical placement of the voice surface's mic row. Every shell height
// (phone, unfolded Duo, landscape, iPad narrow / wide) leaves a different
// amount of free height between the top bar and the bottom row; this splits it
// into the context slot above the mic and the gap below it with one rule, so
// the mic sits centred in the area below the top bar on every device.

import CoreGraphics

public enum VoiceMicPlacement {
    /// Never let the mic touch the bottom row.
    public static let minimumGap: CGFloat = 10

    /// Context slot height for a free height (`contextAndGap` = slot + gap).
    /// Centred means the slot above the mic equals the gap plus the bottom row
    /// below it, but the slot never drops under `minimumContextHeight` (the
    /// live transcript) and the gap never under `minimumGap`.
    public static func contextHeight(
        contextAndGap: CGFloat,
        bottomRowHeight: CGFloat,
        minimumContextHeight: CGFloat
    ) -> CGFloat {
        let centred = (contextAndGap + bottomRowHeight) / 2
        let ceiling = max(0, contextAndGap - minimumGap)
        return min(ceiling, max(minimumContextHeight, centred))
    }
}
