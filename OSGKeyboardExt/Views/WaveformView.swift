// WaveformView.swift
// OSGKeyboard · Keyboard Extension
//
// Symmetric, real-time driven waveform. 18 bars centred around a vertical
// axis. The dominant bar is driven by the current RMS; surrounding bars
// decay on a small position-based curve so the visual feels like a
// horizontal speaker cone, not random noise.

import SwiftUI
import OSGKeyboardShared

struct WaveformView: View {
    let level: Double          // 0...1, smoothed RMS
    let barCount: Int
    let color: Color
    let active: Bool           // when false, bars collapse to a thin resting line

    init(
        level: Double,
        barCount: Int = 18,
        color: Color = Palette.recordRed,
        active: Bool = true
    ) {
        self.level = max(0, min(1, level))
        self.barCount = barCount
        self.color = color
        self.active = active
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2.4, height: height(for: i, time: context.date.timeIntervalSinceReferenceDate))
                        .opacity(active ? 1.0 : 0.45)
                }
            }
        }
    }

    private func height(for index: Int, time: TimeInterval) -> CGFloat {
        guard active else { return 4 }
        let centre = Double(barCount - 1) / 2.0
        let distance = abs(Double(index) - centre) / max(centre, 1)
        // Per-bar small wobble so the line is alive but tied to level.
        let phase = sin(time * 4.0 + Double(index) * 0.45)
        let wobble = 0.18 * phase
        let magnitude = max(0, min(1, Double(level) + wobble))
        let profile = 1.0 - pow(distance, 1.4) * 0.85
        return CGFloat(max(6, 32 * magnitude * profile))
    }
}
