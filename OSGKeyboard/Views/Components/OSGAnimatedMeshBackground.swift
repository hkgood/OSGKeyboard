// OSGAnimatedMeshBackground.swift
// OSGKeyboard · Main App
//
// A slowly-flowing MeshGradient background (iOS 18+, deployment target iOS 26).
// System-native Metal acceleration, no third-party dependencies, 0 KB of assets.
//
// Design notes:
// - 3×3 grid keeps render cost low; corner points stay fixed (no clipping at edges).
// - Only the 4 inner control points + 4 mid-edge points drift; this avoids the
//   gradient "snapping" at the edges of the parent view.
// - `TimelineView(.animation(minimumInterval: 1.0/30.0))` caps redraw at 30 fps
//   (backgrounds do not need 120 Hz) — roughly halves GPU vs. uncapped TimelineView.
// - `accessibilityReduceMotion` → static frame at phase = 0 (Apple HIG).
// - Palette is the same near-black base used across the rest of the app
//   (`Color(red: 0.06, green: 0.06, blue: 0.07)`) with cool-warm accents that
//   sit in the "premium, calm, late-night" register — fits the Typeless vibe.

import SwiftUI

@available(iOS 18.0, *)
struct OSGAnimatedMeshBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Animation period in seconds for a full color cycle. Longer = calmer.
    var period: Double = 14.0

    /// Optional palette override. Defaults to a deep indigo / amber / teal set.
    var palette: AnimatedMeshPalette = .aurora

    /// Pause the animation at the current frame. Useful for App Store
    /// screenshot capture or for "preview" hosts that want a still image.
    var paused: Bool = false

    var body: some View {
        if reduceMotion || paused {
            MeshGradient(
                width: 3,
                height: 3,
                points: Self.staticPoints,
                colors: palette.colors,
                smoothsColors: true,
                colorSpace: .perceptual
            )
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate / period
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: Self.animatedPoints(phase: phase),
                    colors: Self.animatedColors(base: palette.colors, phase: phase),
                    smoothsColors: true,
                    colorSpace: .perceptual
                )
            }
        }
    }
}

// MARK: - Geometry

@available(iOS 18.0, *)
private extension OSGAnimatedMeshBackground {
    /// 9 SIMD2 control points for a 3×3 mesh, top-left → bottom-right, row-major.
    /// Corner points (0, 3, 6, 8) stay fixed; the rest drift on a slow sinusoid.
    static let staticPoints: [SIMD2<Float>] = [
        SIMD2(0.0, 0.0), SIMD2(0.5, 0.0), SIMD2(1.0, 0.0),
        SIMD2(0.0, 0.5), SIMD2(0.5, 0.5), SIMD2(1.0, 0.5),
        SIMD2(0.0, 1.0), SIMD2(0.5, 1.0), SIMD2(1.0, 1.0)
    ]

    static func animatedPoints(phase: Double) -> [SIMD2<Float>] {
        // Use distinct incommensurable frequencies so the loop never visibly
        // repeats inside a normal viewing session.
        let p = Float(phase)
        let cos1 = cos(p * 0.27) * 0.18
        let cos2 = cos(p * 0.41 + 1.7) * 0.16
        let sin1 = sin(p * 0.33 + 0.4) * 0.18
        let sin2 = sin(p * 0.51 + 2.1) * 0.14
        return [
            SIMD2(0.0, 0.0),                                   // top-left  (fixed)
            SIMD2(0.5 + cos1, 0.0),                            // top-mid
            SIMD2(1.0, 0.0),                                   // top-right (fixed)
            SIMD2(0.0, 0.5 + sin1),                            // left-mid
            SIMD2(0.5 + cos2, 0.5 + sin2),                     // center
            SIMD2(1.0, 0.5 + cos1 * 0.7),                      // right-mid
            SIMD2(0.0, 1.0),                                   // bottom-left  (fixed)
            SIMD2(0.5 + sin2, 1.0),                            // bottom-mid
            SIMD2(1.0, 1.0)                                    // bottom-right (fixed)
        ]
    }

    /// Slowly cycle each color's hue by a tiny amount so the gradient looks
    /// alive without ever crossing into "screensaver" territory.
    static func animatedColors(base: [Color], phase: Double) -> [Color] {
        base.enumerated().map { index, color in
            let shift = cos(phase + Double(index) * 0.31) * 0.025
            return color.shiftedHue(by: shift)
        }
    }
}

// MARK: - Palettes

/// Named color sets. Each is 9 colors arranged to read as a smooth
/// "calm cloud" — low saturation, low brightness, no obvious focal point.
struct AnimatedMeshPalette: Sendable {
    var colors: [Color]

    /// Deep indigo / amber / teal. Default — works for the dark home screen.
    static let aurora = AnimatedMeshPalette(colors: [
        Color(red: 0.06, green: 0.07, blue: 0.13),  // top-left
        Color(red: 0.10, green: 0.08, blue: 0.20),  // top-mid
        Color(red: 0.05, green: 0.10, blue: 0.18),  // top-right
        Color(red: 0.12, green: 0.09, blue: 0.16),  // left-mid
        Color(red: 0.18, green: 0.11, blue: 0.22),  // center  ← deepest violet
        Color(red: 0.08, green: 0.12, blue: 0.20),  // right-mid
        Color(red: 0.16, green: 0.10, blue: 0.10),  // bottom-left  (amber hint)
        Color(red: 0.10, green: 0.08, blue: 0.18),  // bottom-mid
        Color(red: 0.05, green: 0.09, blue: 0.14)   // bottom-right
    ])

    /// Cooler / more "Apple" feel — slate blue, steel, ice.
    static let polar = AnimatedMeshPalette(colors: [
        Color(red: 0.05, green: 0.07, blue: 0.10),
        Color(red: 0.09, green: 0.12, blue: 0.18),
        Color(red: 0.07, green: 0.09, blue: 0.14),
        Color(red: 0.10, green: 0.13, blue: 0.18),
        Color(red: 0.13, green: 0.16, blue: 0.22),
        Color(red: 0.08, green: 0.10, blue: 0.16),
        Color(red: 0.06, green: 0.10, blue: 0.16),
        Color(red: 0.09, green: 0.11, blue: 0.18),
        Color(red: 0.05, green: 0.07, blue: 0.12)
    ])

    /// Warm "candlelight" — fits evening writing session vibes.
    static let ember = AnimatedMeshPalette(colors: [
        Color(red: 0.08, green: 0.06, blue: 0.05),
        Color(red: 0.14, green: 0.09, blue: 0.06),
        Color(red: 0.10, green: 0.07, blue: 0.06),
        Color(red: 0.16, green: 0.10, blue: 0.07),
        Color(red: 0.22, green: 0.13, blue: 0.08),
        Color(red: 0.12, green: 0.08, blue: 0.07),
        Color(red: 0.10, green: 0.06, blue: 0.05),
        Color(red: 0.15, green: 0.09, blue: 0.06),
        Color(red: 0.08, green: 0.06, blue: 0.05)
    ])
}

// MARK: - Helpers

private extension Color {
    /// Shift the color's hue by a small amount (-1.0 ... 1.0 wraps the wheel).
    /// Used purely for subtle gradient breathing — keep `amount` ≤ 0.05.
    func shiftedHue(by amount: Double) -> Color {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        hue += CGFloat(amount)
        hue = hue.truncatingRemainder(dividingBy: 1.0)
        if hue < 0 { hue += 1 }
        return Color(hue: Double(hue), saturation: Double(saturation), brightness: Double(brightness), opacity: Double(alpha))
    }
}

// MARK: - Preview

#Preview("Aurora (dark)") {
    ZStack {
        OSGAnimatedMeshBackground(palette: .aurora)
        Text("aurora")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}

#Preview("Polar (dark)") {
    ZStack {
        OSGAnimatedMeshBackground(palette: .polar)
        Text("polar")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}

#Preview("Ember (dark)") {
    ZStack {
        OSGAnimatedMeshBackground(palette: .ember)
        Text("ember")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(.white.opacity(0.85))
    }
    .ignoresSafeArea()
    .preferredColorScheme(.dark)
}
