// RecordButton.swift
// OSGKeyboard · Shared
//
// Tap-to-toggle mic button shared between the keyboard extension and
// host-app keyboard preview surfaces.

import SwiftUI

public struct RecordButton: View {
    @Environment(\.themePalette) private var palette: ThemePalette

    public enum Phase: Equatable {
        /// Green — host ready; tap records immediately.
        case idleReady
        /// Orange — voice input unavailable (missing key, session not ready, etc.).
        case idleUnavailable
        case recording
        case processing
        case error
    }

    public let phase: Phase
    public let level: Double
    public let remainingSeconds: Int?
    public let isEnabled: Bool
    public let onToggle: () -> Void

    @State private var breath = false

    public init(
        phase: Phase,
        level: Double,
        remainingSeconds: Int? = nil,
        isEnabled: Bool = true,
        onToggle: @escaping () -> Void
    ) {
        self.phase = phase
        self.level = level
        self.remainingSeconds = remainingSeconds
        self.isEnabled = isEnabled
        self.onToggle = onToggle
    }

    private var isUrgent: Bool {
        guard phase == .recording, let remainingSeconds else { return false }
        return remainingSeconds <= 10
    }

    private enum Layout {
        static let disc: CGFloat = 95
        static let outerRing: CGFloat = 106
        static let breathRing: CGFloat = 100
        static let glow: CGFloat = 119
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(palette.recordRed.opacity(isUrgent ? 0.55 : 0.35), lineWidth: isUrgent ? 3 : 2)
                .frame(width: Layout.breathRing, height: Layout.breathRing)
                .scaleEffect(breath ? 1.18 : 0.95)
                .opacity(phase == .recording ? 1 : 0)
                .animation(Motion.breath, value: breath)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [palette.recordRed.opacity(0.55), .clear],
                        center: .center,
                        startRadius: 46,
                        endRadius: 92
                    )
                )
                .frame(width: Layout.glow, height: Layout.glow)
                .opacity(phase == .recording ? 0.4 + level * 0.6 : 0)
                .blur(radius: 18)
                .animation(Motion.soft, value: phase)
                .animation(Motion.soft, value: level)

            Circle()
                .stroke(Color.white.opacity(isIdle ? 0.08 : 0.12), lineWidth: 0.5)
                .frame(width: Layout.outerRing, height: Layout.outerRing)

            ZStack {
                Circle()
                    .fill(discGradient)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .blendMode(.overlay)

                Group {
                    switch phase {
                    case .idleReady, .idleUnavailable:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(.white)
                    case .recording:
                        VStack(spacing: 3) {
                            if let remainingSeconds {
                                Text(formatRemaining(remainingSeconds))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .offset(y: 3)
                            }
                            WaveformView(
                                level: level,
                                color: Color(red: 1.0, green: 0.78, blue: 0.78),
                                active: true
                            )
                            .frame(width: 73, height: 32)
                            .opacity(0.4)
                            .scaleEffect(0.96)
                        }
                        .transition(.opacity)
                    case .processing:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(palette.textPrimary)
                            .scaleEffect(1.25)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(palette.warning)
                    }
                }
            }
            .frame(width: Layout.disc, height: Layout.disc)
            .animation(Motion.soft, value: phase)
            .animation(Motion.soft, value: remainingSeconds)
        }
        .contentShape(Circle())
        .onTapGesture {
            guard phase != .processing else { return }
            guard isEnabled || phase == .idleUnavailable else { return }
            onToggle()
        }
        .onAppear { breath = (phase == .recording) }
        .onChange(of: phase) { _, new in
            breath = (new == .recording)
        }
        .accessibilityLabel(Text(SharedL10n.string("keyboard.tapToTalkA11y")))
    }

    private var isIdle: Bool {
        switch phase {
        case .idleReady, .idleUnavailable:
            return true
        case .recording, .processing, .error:
            return false
        }
    }

    private func formatRemaining(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
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
        case .error, .idleUnavailable:
            return LinearGradient(
                colors: [palette.warning.opacity(0.85), palette.warning.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .idleReady:
            return LinearGradient(
                colors: [palette.accent.opacity(0.95), palette.accent.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
