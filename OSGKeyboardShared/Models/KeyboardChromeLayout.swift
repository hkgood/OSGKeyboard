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
    /// The voice surface is a sparse control cluster over a transparent
    /// background, so filling an iPad's width buys no visual width and only
    /// parks delete/return at the screen edges. The typing surface has the
    /// opposite need (a key grid must fill the width to match the system
    /// keyboard), which is why it no longer shares this constant.
    public static let voiceContentMaxWidth: CGFloat = 700

    /// Hosts that draw the keyboard-style voice key row span the typing width:
    /// the row, top bar and logo must sit on the same frame as the typing keys,
    /// or they jump sideways on every tab switch.
    public static func voiceContentWidthCap(usesVoiceKeyRow: Bool) -> CGFloat {
        usesVoiceKeyRow ? .infinity : voiceContentMaxWidth
    }

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

    /// System-sized iPhone-shaped keys for a phone host with regular space on
    /// both axes — the unfolded iPhone Duo inner display. Landscape Max-size
    /// iPhones are regular × compact and keep the phone metrics.
    public static func usesExpandedPhoneMetrics(
        isPad: Bool,
        hasRegularWidth: Bool,
        hasRegularHeight: Bool
    ) -> Bool {
        !isPad && hasRegularWidth && hasRegularHeight
    }

    /// Shorter phone panel whenever the host is vertically compact: every
    /// iPhone in landscape, including the folded iPhone Duo. Compact-height
    /// iPad windows keep their own metrics.
    public static func usesCompactHeightPhoneMetrics(isPad: Bool, hasCompactHeight: Bool) -> Bool {
        !isPad && hasCompactHeight
    }

    /// iPad always draws its own globe key. Elsewhere UIKit decides: Face ID
    /// iPhones get a system switch below the keyboard, while the unfolded
    /// iPhone Duo and Home-button iPhones need the keyboard to provide one.
    public static func showsInputModeSwitchKey(
        isPad: Bool,
        systemRequiresSwitchKey: Bool
    ) -> Bool {
        isPad || systemRequiresSwitchKey
    }

    /// Wide metrics need iPad-scale keys *and* enough width to justify them.
    public static func usesWideIPadMetrics(isIPad: Bool, width: CGFloat) -> Bool {
        isIPad && width >= wideIPadWidthThreshold
    }

    /// Below this width the voice microphone capsule shrinks (Display Zoom on
    /// a small iPhone, iPad Slide Over). Every current iPhone is wider.
    public static let compactVoiceWidthThreshold: CGFloat = 350
    /// Below this width an iPad-metrics voice surface uses its smaller circles.
    public static let compactIPadVoiceWidthThreshold: CGFloat = 420

    /// `width == 0` means "not measured yet" and never counts as compact.
    public static func usesCompactVoiceMetrics(width: CGFloat) -> Bool {
        width > 0 && width < compactVoiceWidthThreshold
    }

    public static func usesCompactIPadVoiceMetrics(isIPad: Bool, width: CGFloat) -> Bool {
        isIPad && width > 0 && width < compactIPadVoiceWidthThreshold
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
