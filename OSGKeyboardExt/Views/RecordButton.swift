// RecordButton.swift
// OSGKeyboard · Keyboard Extension
//
// Tap-to-toggle mic: tap once to start, tap again to stop. Shows a
// remaining-time countdown while recording; last 10 seconds turn red.

import SwiftUI
import OSGKeyboardShared

struct RecordButton: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case error
    }

    let phase: Phase
    let level: Double          // 0...1
    /// Seconds left in the current utterance; shown only while recording.
    let remainingSeconds: Int?
    let onToggle: () -> Void

    @State private var breath: Bool = false

    init(
        phase: Phase,
        level: Double,
        remainingSeconds: Int? = nil,
        onToggle: @escaping () -> Void
    ) {
        self.phase = phase
        self.level = level
        self.remainingSeconds = remainingSeconds
        self.onToggle = onToggle
    }

    private var isUrgent: Bool {
        guard phase == .recording, let remainingSeconds else { return false }
        return remainingSeconds <= 10
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.recordRed.opacity(isUrgent ? 0.55 : 0.35), lineWidth: isUrgent ? 3 : 2)
                .frame(width: 150, height: 150)
                .scaleEffect(breath ? 1.18 : 0.95)
                .opacity(phase == .recording ? 1 : 0)
                .animation(Motion.breath, value: breath)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.recordRed.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 50,
                        endRadius: 100
                    )
                )
                .frame(width: 200, height: 200)
                .opacity(phase == .recording ? 0.4 + level * 0.6 : 0)
                .blur(radius: 18)
                .animation(Motion.soft, value: phase)
                .animation(Motion.soft, value: level)

            Circle()
                .stroke(
                    Color.white.opacity(phase == .idle ? 0.08 : 0.12),
                    lineWidth: 0.5
                )
                .frame(width: 140, height: 140)

            ZStack {
                Circle()
                    .fill(discGradient)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .blendMode(.overlay)

                Group {
                    switch phase {
                    case .idle:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.white)
                    case .recording:
                        VStack(spacing: 4) {
                            if let remainingSeconds {
                                Text(formatRemaining(remainingSeconds))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            WaveformView(
                                level: level,
                                color: Color(red: 1.0, green: 0.78, blue: 0.78),
                                active: true
                            )
                                .frame(width: 72, height: 32)
                        }
                        .transition(.opacity)
                    case .processing:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(palette.textPrimary)
                            .scaleEffect(2.5)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(palette.warning)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .animation(Motion.soft, value: phase)
            .animation(Motion.soft, value: remainingSeconds)
        }
        .contentShape(Circle())
        .onTapGesture {
            guard phase != .processing else { return }
            onToggle()
        }
        .onAppear { breath = (phase == .recording) }
        .onChange(of: phase) { _, new in
            breath = (new == .recording)
        }
        .accessibilityLabel(ExtL10n.text("keyboard.tapToTalkA11y"))
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    private var discGradient: LinearGradient {
        switch phase {
        case .recording:
            let colors: [Color] = isUrgent
                ? [palette.recordRed, palette.recordRed.opacity(0.85)]
                : [palette.recordRed.opacity(0.95), palette.recordRed.opacity(0.75)]
            return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        case .processing:
            return LinearGradient(
                colors: [palette.surfaceElevated, palette.surface],
                startPoint: .top,
                endPoint: .bottom
            )
        case .error:
            return LinearGradient(
                colors: [palette.warning.opacity(0.85), palette.warning.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .idle:
            return LinearGradient(
                colors: [
                    palette.accent.opacity(0.95),
                    palette.accent.opacity(0.75)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
