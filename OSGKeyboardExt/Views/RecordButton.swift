// RecordButton.swift
// OSGKeyboard · Keyboard Extension
//
// The hero control. 120 pt primary disc with a soft inner gradient, a
// breathing outer ring while recording, and a centred waveform that maps
// directly to the real audio RMS. Idle / recording / processing are three
// distinct visual states — no flicker, no surprise transitions.

import SwiftUI
import OSGKeyboardShared

struct RecordButton: View {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
        case error
    }

    let phase: Phase
    let level: Double          // 0...1
    let onPressBegan: () -> Void
    let onPressEnded:  () -> Void
    let onTap:         () -> Void

    @GestureState private var isPressed: Bool = false
    @State private var breath: Bool = false

    init(
        phase: Phase,
        level: Double,
        onPressBegan: @escaping () -> Void,
        onPressEnded:  @escaping () -> Void,
        onTap:         @escaping () -> Void
    ) {
        self.phase = phase
        self.level = level
        self.onPressBegan = onPressBegan
        self.onPressEnded = onPressEnded
        self.onTap = onTap
    }

    var body: some View {
        ZStack {
            // Outer breathing ring (recording only)
            Circle()
                .stroke(Palette.recordRed.opacity(0.35), lineWidth: 2)
                .frame(width: 150, height: 150)
                .scaleEffect(breath ? 1.18 : 0.95)
                .opacity(phase == .recording ? 1 : 0)
                .animation(Motion.breath, value: breath)

            // Halo: soft red glow that intensifies with input level
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Palette.recordRed.opacity(0.55), .clear],
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

            // Secondary outer ring (always present, dimmer when idle)
            Circle()
                .stroke(
                    Color.white.opacity(phase == .idle ? 0.08 : 0.12),
                    lineWidth: 0.5
                )
                .frame(width: 140, height: 140)

            // Main disc with gradient + soft inner highlight
            ZStack {
                Circle()
                    .fill(discGradient)
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    .blendMode(.overlay)

                // Centre content — switches by phase
                Group {
                    switch phase {
                    case .idle:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                    case .recording:
                        WaveformView(level: level, active: true)
                            .frame(width: 80, height: 44)
                            .transition(.opacity)
                    case .processing:
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Palette.textPrimary)
                            .scaleEffect(1.2)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            .frame(width: 120, height: 120)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
            .animation(Motion.quick, value: isPressed)
            .animation(Motion.soft, value: phase)
        }
        .contentShape(Circle())
        // Press-to-talk: act on the FIRST touch-down, not after a 150 ms
        // minimum duration. That's what Typeless feels like, and it's what
        // makes the keyboard feel responsive. A tap (very short press) is
        // interpreted as "toggle" for the secondary action (onTap), not
        // "record" — the recording only fires if the press lasts long
        // enough to read as intentional. This avoids the previous bug
        // where every single tap fired both onPressBegan AND onTap.
        .gesture(
            LongPressGesture(minimumDuration: 0.18)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($isPressed) { value, state, _ in
                    switch value {
                    case .second(true, _): state = true
                    default: state = false
                    }
                }
                .onChanged { value in
                    if case .second(true, _) = value, !pressArmed {
                        pressArmed = true
                        onPressBegan()
                    }
                }
                .onEnded { _ in
                    if pressArmed { pressArmed = false; onPressEnded() }
                }
        )
        .simultaneousGesture(
            // Pure tap: only fires when the user lifts before the long-press
            // threshold. This becomes the "secondary action" (e.g. cycle
            // mode). It is paired with, not conflicting with, the long-press.
            TapGesture(count: 1)
                .onEnded {
                    if !pressArmed { onTap() }
                }
        )
        .onAppear { breath = (phase == .recording) }
        .onChange(of: phase) { _, new in
            breath = (new == .recording)
        }
        .accessibilityLabel(Text("Push to talk"))
    }

    @State private var pressArmed: Bool = false

    private var discGradient: LinearGradient {
        switch phase {
        case .recording:
            return LinearGradient(
                colors: [Palette.recordRed.opacity(0.95), Palette.recordRed.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .processing:
            return LinearGradient(
                colors: [Palette.surfaceElevated, Palette.surface],
                startPoint: .top,
                endPoint: .bottom
            )
        case .error:
            return LinearGradient(
                colors: [Palette.warning.opacity(0.85), Palette.warning.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .idle:
            return LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
