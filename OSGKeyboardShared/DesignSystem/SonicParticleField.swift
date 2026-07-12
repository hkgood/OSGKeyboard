// SonicParticleField.swift
// OSGKeyboard · Shared Design System
//
// Ambient radial sonic-wave particles for onboarding welcome screens.
// Pure SwiftUI Canvas + TimelineView — no Metal / SpriteKit dependency.

import SwiftUI

// MARK: - Ripple

private struct SonicRipple: Identifiable {
    let id = UUID()
    let origin: CGPoint
    let bornAt: TimeInterval
}

// MARK: - Particle seed (immutable layout)

private struct SonicParticleSeed: Sendable {
    let ring: Int
    let angle: Double
    let phase: Double
    let size: CGFloat
}

// MARK: - View

/// Radial sonic-wave particle field with touch / pointer interaction.
/// Intended as a decorative backdrop behind onboarding hero content.
public struct SonicParticleField: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Optional accent override; defaults to `themePalette.accent`.
    public var accent: Color?
    /// Focal point for the pulse rings, in unit coordinates of the field bounds.
    public var focalPoint: UnitPoint
    /// When false, particles animate but ignore pointer input.
    public var isInteractive: Bool

    @State private var touchLocation: CGPoint?
    @State private var isTouching = false
    @State private var ripples: [SonicRipple] = []

    public init(
        accent: Color? = nil,
        focalPoint: UnitPoint = .center,
        isInteractive: Bool = true
    ) {
        self.accent = accent
        self.focalPoint = focalPoint
        self.isInteractive = isInteractive
    }

    private var resolvedAccent: Color {
        accent ?? palette.accent
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0)) { timeline in
            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(
                    x: size.width * focalPoint.x,
                    y: size.height * focalPoint.y
                )
                let time = timeline.date.timeIntervalSinceReferenceDate
                let motionScale = reduceMotion ? 0.18 : 1.0

                ZStack {
                    RadialGradient(
                        colors: [
                            resolvedAccent.opacity(reduceMotion ? 0.05 : 0.10),
                            resolvedAccent.opacity(0.03),
                            palette.background.opacity(0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: min(size.width, size.height) * 0.52
                    )

                    Canvas { context, canvasSize in
                        drawField(
                            in: &context,
                            size: canvasSize,
                            center: center,
                            time: time * motionScale,
                            motionScale: motionScale
                        )
                    }
                }
                .contentShape(Rectangle())
                .gesture(interactionGesture(in: size, time: time))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(isInteractive)
    }

    // MARK: - Drawing

    private func drawField(
        in context: inout GraphicsContext,
        size: CGSize,
        center: CGPoint,
        time: TimeInterval,
        motionScale: Double
    ) {
        let maxDimension = max(size.width, size.height)
        let ringSpacing = maxDimension * 0.075
        let baseRadius = maxDimension * 0.06
        let influenceRadius = maxDimension * 0.22

        drawRipples(
            in: &context,
            time: time,
            maxRadius: maxDimension * 0.55
        )

        for seed in Self.particleSeeds {
            let pulse = (time * 0.42 + seed.phase).truncatingRemainder(dividingBy: 1.0)
            let wobble = sin(time * 2.4 + seed.angle * 3.0) * 0.018
            let angle = seed.angle + wobble

            let ringRadius = baseRadius + Double(seed.ring) * ringSpacing
            let expansion = pulse * ringSpacing * 0.92
            var radius = ringRadius + expansion

            // Soft sonic bulge — particles swell mid-pulse.
            let swell = sin(pulse * .pi) * ringSpacing * 0.08
            radius += swell

            var position = polarPoint(center: center, radius: radius, angle: angle)
            position = applyTouchInfluence(
                to: position,
                touch: touchLocation,
                influenceRadius: influenceRadius
            )

            var opacity = (1.0 - pulse) * 0.62 + 0.12
            opacity += sin(time * 3.1 + seed.phase * 8.0) * 0.06
            opacity = max(0.08, min(0.78, opacity))

            if motionScale < 1 {
                opacity *= 0.55
            }

            opacity += rippleBoost(at: position, time: time, maxRadius: maxDimension * 0.55)

            let particleColor = resolvedAccent.opacity(opacity)
            let rect = CGRect(
                x: position.x - seed.size * 0.5,
                y: position.y - seed.size * 0.5,
                width: seed.size,
                height: seed.size
            )

            context.fill(
                Path(ellipseIn: rect),
                with: .color(particleColor)
            )
        }
    }

    private func drawRipples(
        in context: inout GraphicsContext,
        time: TimeInterval,
        maxRadius: CGFloat
    ) {
        for ripple in ripples {
            let age = time - ripple.bornAt
            guard age > 0, age < 2.4 else { continue }

            let progress = age / 2.4
            let radius = maxRadius * CGFloat(progress)
            let opacity = (1.0 - progress) * 0.28
            let lineWidth = max(0.8, 2.4 - progress * 1.4)

            var ringContext = context
            ringContext.stroke(
                Path(ellipseIn: CGRect(
                    x: ripple.origin.x - radius,
                    y: ripple.origin.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )),
                with: .color(resolvedAccent.opacity(opacity)),
                lineWidth: lineWidth
            )
        }
    }

    private func rippleBoost(at point: CGPoint, time: TimeInterval, maxRadius: CGFloat) -> Double {
        var boost = 0.0
        for ripple in ripples {
            let age = time - ripple.bornAt
            guard age > 0, age < 2.4 else { continue }

            let progress = age / 2.4
            let radius = Double(maxRadius) * progress
            let dist = hypot(point.x - ripple.origin.x, point.y - ripple.origin.y)
            let band = abs(dist - radius)
            if band < 18 {
                boost += (1.0 - band / 18.0) * (1.0 - progress) * 0.35
            }
        }
        return min(boost, 0.4)
    }

    private func polarPoint(center: CGPoint, radius: Double, angle: Double) -> CGPoint {
        CGPoint(
            x: center.x + CGFloat(cos(angle) * radius),
            y: center.y + CGFloat(sin(angle) * radius)
        )
    }

    private func applyTouchInfluence(
        to point: CGPoint,
        touch: CGPoint?,
        influenceRadius: CGFloat
    ) -> CGPoint {
        guard let touch else { return point }

        let dx = point.x - touch.x
        let dy = point.y - touch.y
        let distance = hypot(dx, dy)
        guard distance > 0.5, distance < influenceRadius else { return point }

        let normalized = (influenceRadius - distance) / influenceRadius
        let strength = CGFloat(normalized * normalized) * (isTouching ? 22 : 10)
        return CGPoint(
            x: point.x + dx / distance * strength,
            y: point.y + dy / distance * strength
        )
    }

    // MARK: - Interaction

    private func interactionGesture(in size: CGSize, time: TimeInterval) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isInteractive else { return }
                touchLocation = value.location
                isTouching = true
                registerRipple(at: value.location, time: time)
            }
            .onEnded { _ in
                isTouching = false
                touchLocation = nil
            }
    }

    private func registerRipple(at location: CGPoint, time: TimeInterval) {
        let shouldAdd: Bool
        if let last = ripples.last {
            let moved = hypot(location.x - last.origin.x, location.y - last.origin.y)
            let elapsed = time - last.bornAt
            shouldAdd = moved > 36 || elapsed > 0.38
        } else {
            shouldAdd = true
        }

        guard shouldAdd else { return }

        ripples.append(SonicRipple(origin: location, bornAt: time))
        ripples = ripples.filter { time - $0.bornAt < 2.6 }
    }

    // MARK: - Particle layout

    private static let particleSeeds: [SonicParticleSeed] = {
        var seeds: [SonicParticleSeed] = []
        let ringCount = 7
        let particlesPerRing = [14, 18, 22, 26, 30, 34, 38]

        for ring in 0..<ringCount {
            let count = particlesPerRing[ring]
            for index in 0..<count {
                let angle = (Double(index) / Double(count)) * (.pi * 2.0)
                    + Double(ring) * 0.11
                let phase = Double(ring) * 0.13 + Double(index) * 0.017
                let size = CGFloat(1.6 + (Double(index + ring) * 0.07).truncatingRemainder(dividingBy: 1.9))
                seeds.append(SonicParticleSeed(ring: ring, angle: angle, phase: phase, size: size))
            }
        }
        return seeds
    }()
}
