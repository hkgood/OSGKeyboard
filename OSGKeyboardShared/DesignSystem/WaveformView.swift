// WaveformView.swift
// OSGKeyboard · Shared
//
// Symmetric, real-time driven waveform. Shared between the keyboard
// extension and any host-app preview that mirrors the mic UI.

import SwiftUI

public struct WaveformView: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    public let level: Double
    public let barCount: Int
    public let color: Color?
    public let active: Bool

    public init(
        level: Double,
        barCount: Int = 18,
        color: Color? = nil,
        active: Bool = true
    ) {
        self.level = max(0, min(1, level))
        self.barCount = barCount
        self.color = color
        self.active = active
    }

    private var resolvedColor: Color {
        color ?? palette.recordRed
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(resolvedColor)
                        .frame(
                            width: 2.4,
                            height: height(for: index, time: context.date.timeIntervalSinceReferenceDate)
                        )
                        .opacity(active ? 1.0 : 0.45)
                }
            }
        }
    }

    private func height(for index: Int, time: TimeInterval) -> CGFloat {
        guard active else { return 4 }
        let centre = Double(barCount - 1) / 2.0
        let distance = abs(Double(index) - centre) / max(centre, 1)
        let phase = sin(time * 4.0 + Double(index) * 0.45)
        let wobble = 0.18 * phase
        let magnitude = max(0, min(1, Double(level) + wobble))
        let profile = 1.0 - pow(distance, 1.4) * 0.85
        return CGFloat(max(6, 32 * magnitude * profile))
    }
}
