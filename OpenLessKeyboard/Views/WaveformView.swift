// WaveformView.swift
// OSGKeyboard · Keyboard Extension
//
// Simple animated waveform that responds to a 0-1 audio level.

import SwiftUI

public struct WaveformView: View {
    public let level: Double   // 0...1
    public let barCount: Int
    public let color: Color

    public init(level: Double, barCount: Int = 5, color: Color = .red) {
        self.level = max(0, min(1, level))
        self.barCount = barCount
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: heightFor(index: i))
                    .animation(.easeInOut(duration: 0.18), value: level)
            }
        }
    }

    private func heightFor(index: Int) -> CGFloat {
        // Center bars taller; outer shorter — symmetric pattern
        let center = Double(barCount - 1) / 2.0
        let distance = abs(Double(index) - center) / max(center, 1)
        let base = max(6, 28 * level)
        return CGFloat(base * (1.0 - distance * 0.4))
    }
}
