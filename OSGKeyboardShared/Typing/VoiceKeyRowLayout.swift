// VoiceKeyRowLayout.swift
// OSGKeyboard · Shared
//
// Keyboard-style voice bottom row for wide hosts (iPad, unfolded iPhone Duo).

import CoreGraphics

/// Horizontal geometry of the wide-host voice bottom row:
///
///     [leadingSide][leadingContext][    send    ][trailingContext][trailingSide]
///
/// - The four icon keys (space / undo / edit / delete) share one width and send
///   is exactly twice as wide, so the primary action reads as the main key while
///   the row fills edge to edge with uniform gaps. The row is symmetric, so send
///   sits on the centre line under the microphone.
/// - No globe: the voice surface leaves input-mode switching to the typing tab.
/// - Context slots (undo / edit) exist even while the keys are disabled, so
///   nothing in the row shifts when they toggle.
///
/// Coordinates are relative to the row's own leading edge.
public struct VoiceKeyRowLayout: Equatable, Sendable {
    public struct Slot: Equatable, Sendable {
        public let minX: CGFloat
        public let width: CGFloat

        public var midX: CGFloat { minX + width / 2 }
        public var maxX: CGFloat { minX + width }

        public init(minX: CGFloat, width: CGFloat) {
            self.minX = minX
            self.width = width
        }
    }

    /// Send width as a multiple of one icon key.
    public static let sendWidthMultiplier: CGFloat = 2
    /// Below this host width the icon keys would shrink past a comfortable
    /// touch target, so narrower hosts keep the phone's circle cluster.
    public static let minimumHostWidth: CGFloat = 500

    public let leadingSide: Slot
    public let leadingContext: Slot
    public let send: Slot
    public let trailingContext: Slot
    public let trailingSide: Slot

    /// Wide hosts only: iPad-scale metrics, the expanded-phone tier, or a
    /// landscape iPhone (whose shorter panel has no room for two circle rows),
    /// with enough width for the row. Portrait iPhones keep the circle
    /// cluster, which suits one-handed thumb reach.
    public static func isAvailable(
        usesIPadMetrics: Bool,
        usesExpandedPhoneMetrics: Bool,
        usesCompactHeightPhoneMetrics: Bool,
        hostWidth: CGFloat
    ) -> Bool {
        (usesIPadMetrics || usesExpandedPhoneMetrics || usesCompactHeightPhoneMetrics)
            && hostWidth >= minimumHostWidth
    }

    /// - Parameter rowWidth: The row's width, i.e. the same width the typing bottom row spans.
    public static func make(rowWidth: CGFloat) -> VoiceKeyRowLayout {
        let spacing = KeyboardChromeLayout.actionKeySpacing

        // 4 icon keys + one send key worth `sendWidthMultiplier` icon keys,
        // with 4 gaps between those five.
        let keySpan = max(0, rowWidth - spacing * 4)
        let keyWidth = keySpan / (4 + sendWidthMultiplier)

        let leadingSide = Slot(minX: 0, width: keyWidth)
        let leadingContext = Slot(minX: leadingSide.maxX + spacing, width: keyWidth)
        let send = Slot(minX: leadingContext.maxX + spacing, width: keyWidth * sendWidthMultiplier)
        let trailingContext = Slot(minX: send.maxX + spacing, width: keyWidth)
        let trailingSide = Slot(minX: trailingContext.maxX + spacing, width: keyWidth)

        return VoiceKeyRowLayout(
            leadingSide: leadingSide,
            leadingContext: leadingContext,
            send: send,
            trailingContext: trailingContext,
            trailingSide: trailingSide
        )
    }
}
