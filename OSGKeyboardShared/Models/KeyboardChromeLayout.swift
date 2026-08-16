// KeyboardChromeLayout.swift
// OSGKeyboard · Shared
//
// Cross-surface dimensions that must stay identical in voice and typing modes.

import CoreGraphics

public enum KeyboardChromeLayout {
    public static let totalHeight: CGFloat = 281
    public static let actionKeyHeight: CGFloat = 50
    /// Shared capsule action height for unified Send and edit-mode controls.
    public static let assistantActionCapsuleHeight: CGFloat = actionKeyHeight
    public static let actionKeyCornerRadius: CGFloat = 10
    /// Shared spacing for every bottom action row. iPad uses a custom globe
    /// slot; iPhone relies on the system-provided switch below the keyboard.
    public static let actionKeySpacing: CGFloat = 8
    /// Globe (🌐) key — small, icon-only.
    public static let globeActionKeyFraction: CGFloat = 0.12
    /// Outer side key — pageSwitch / delete.
    public static let sideActionKeyFraction: CGFloat = 0.18
    /// Center key — space (typing) or return (voice). Widest in the row.
    public static let centerActionKeyFraction: CGFloat = 0.50
    /// Other outer side key — return (typing) or space/delete (voice).
    public static let side2ActionKeyFraction: CGFloat = 0.20
    /// iPad typing bottom row: `[globe · 123 · , · space · . · return]`.
    ///
    /// The four-slot phone row gives the centre key 50% of the width, which on
    /// a full-width landscape iPad turns the space bar into a ~660 pt runway.
    /// The system keyboard spends that width on more keys instead, so iPad
    /// gains comma / period and space settles near the system's ~430 pt.
    public static let iPadGlobeFraction: CGFloat = 0.09
    public static let iPadPageSwitchFraction: CGFloat = 0.13
    public static let iPadPunctuationFraction: CGFloat = 0.09
    public static let iPadSpaceFraction: CGFloat = 0.38
    public static let iPadReturnFraction: CGFloat = 0.22
    /// Five gaps separate the six iPad slots.
    public static let iPadActionKeyGapCount: CGFloat = 5

    public static let horizontalInset: CGFloat = 8
    /// Voice-surface content column cap.
    ///
    /// The voice surface is a sparse cluster — two cursor-drag pads flanking a
    /// fixed 121 pt mic — over a transparent background, so filling an iPad's
    /// width buys no visual width; it only parks delete/return at the screen
    /// edges and turns each drag pad into a ~450 pt runway. The typing surface
    /// has the opposite need (a key grid must fill the width to match the
    /// system keyboard), which is why it no longer shares this constant.
    public static let voiceContentMaxWidth: CGFloat = 700

    /// Width at or above which the typing surface switches to wide-iPad
    /// metrics (taller rows). Chosen to sit between the widest iPad portrait
    /// width (1024 pt on 13") and the narrowest landscape width (1133 pt on
    /// mini), so it tracks real available width rather than device orientation
    /// — Stage Manager and Split View resize into the right bucket for free.
    public static let wideIPadWidthThreshold: CGFloat = 1100

    /// Uses iPad-scale metrics only when the host is both an iPad and currently
    /// exposes regular horizontal space. Compact Split View / Slide Over keeps
    /// the phone-scale layout, while wide iPhones never opt into iPad metrics.
    public static func usesIPadMetrics(isPad: Bool, hasRegularWidth: Bool) -> Bool {
        isPad && hasRegularWidth
    }

    /// Wide metrics need iPad-scale keys *and* enough width to justify them.
    public static func usesWideIPadMetrics(isIPad: Bool, width: CGFloat) -> Bool {
        isIPad && width >= wideIPadWidthThreshold
    }

    /// Splits the width left after three gaps into a 12 / 18 / 50 / 20 row for
    /// layouts that include a globe key, with a wide centre and balanced sides.
    public static func actionKeyWidths(availableWidth: CGFloat) -> (globe: CGFloat, side: CGFloat, center: CGFloat, side2: CGFloat) {
        let keyWidth = max(0, availableWidth - actionKeySpacing * 3)
        return (
            globe: keyWidth * globeActionKeyFraction,
            side: keyWidth * sideActionKeyFraction,
            center: keyWidth * centerActionKeyFraction,
            side2: keyWidth * side2ActionKeyFraction
        )
    }

    /// iPhone bottom row `[side · center · side2]`. Preserve the established
    /// side/centre balance while redistributing the removed globe slot.
    public static func actionKeyWidthsWithoutGlobe(
        availableWidth: CGFloat
    ) -> (side: CGFloat, center: CGFloat, side2: CGFloat) {
        let keyWidth = max(0, availableWidth - actionKeySpacing * 2)
        let fractionTotal = sideActionKeyFraction
            + centerActionKeyFraction
            + side2ActionKeyFraction
        return (
            side: keyWidth * sideActionKeyFraction / fractionTotal,
            center: keyWidth * centerActionKeyFraction / fractionTotal,
            side2: keyWidth * side2ActionKeyFraction / fractionTotal
        )
    }

    /// iPad voice bottom row `[globe · delete · return · space]`. The phone's
    /// 12/18/50/20 split would hand the centre key ~577 pt once the surface
    /// spans an iPad; these fractions keep every key in a usable range while
    /// giving the primary return action a little more room.
    public static let iPadVoiceGlobeFraction: CGFloat = 0.10
    public static let iPadVoiceSideFraction: CGFloat = 0.24
    public static let iPadVoiceCenterFraction: CGFloat = 0.40
    public static let iPadVoiceSide2Fraction: CGFloat = 0.26

    /// iPad variant of `actionKeyWidths` for the voice surface.
    public static func iPadVoiceActionKeyWidths(
        availableWidth: CGFloat
    ) -> (globe: CGFloat, side: CGFloat, center: CGFloat, side2: CGFloat) {
        let keyWidth = max(0, availableWidth - actionKeySpacing * 3)
        return (
            globe: keyWidth * iPadVoiceGlobeFraction,
            side: keyWidth * iPadVoiceSideFraction,
            center: keyWidth * iPadVoiceCenterFraction,
            side2: keyWidth * iPadVoiceSide2Fraction
        )
    }

    /// Six-slot iPad variant of `actionKeyWidths`.
    public static func iPadActionKeyWidths(
        availableWidth: CGFloat
    ) -> (globe: CGFloat, pageSwitch: CGFloat, comma: CGFloat, space: CGFloat, period: CGFloat, return: CGFloat) {
        let keyWidth = max(0, availableWidth - actionKeySpacing * iPadActionKeyGapCount)
        return (
            globe: keyWidth * iPadGlobeFraction,
            pageSwitch: keyWidth * iPadPageSwitchFraction,
            comma: keyWidth * iPadPunctuationFraction,
            space: keyWidth * iPadSpaceFraction,
            period: keyWidth * iPadPunctuationFraction,
            return: keyWidth * iPadReturnFraction
        )
    }
}
