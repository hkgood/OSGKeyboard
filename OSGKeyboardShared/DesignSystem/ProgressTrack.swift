// ProgressTrack.swift
// OSGKeyboard · Shared Design System
//
// Shared linear progress track for consistent height, shape, and background.

import SwiftUI

public struct ProgressTrackSegment {
    let fraction: Double
    let color: Color

    public init(fraction: Double, color: Color) {
        self.fraction = fraction
        self.color = color
    }
}

public struct ProgressTrack: View {
    @Environment(\.themePalette) private var palette

    private let segments: [ProgressTrackSegment]

    public init(segments: [ProgressTrackSegment]) {
        self.segments = segments
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.surfaceElevated.opacity(0.55))

                HStack(spacing: 0) {
                    ForEach(segments.indices, id: \.self) { index in
                        Rectangle()
                            .fill(segments[index].color)
                            .frame(
                                width: proxy.size.width * clampedFraction(
                                    segments[index].fraction
                                )
                            )
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
    }

    private func clampedFraction(_ fraction: Double) -> Double {
        min(max(fraction, 0), 1)
    }
}
