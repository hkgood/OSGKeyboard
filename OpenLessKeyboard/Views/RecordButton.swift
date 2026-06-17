// RecordButton.swift
// OSGKeyboard · Keyboard Extension
//
// Circular push-to-talk button styled like Typeless.
// Pulses red while recording; ripples outward.

import SwiftUI

public struct RecordButton: View {
    public enum Phase { case idle, recording, processing, error(String) }

    public let phase: Phase
    public let onPressBegan: () -> Void
    public let onPressEnded: () -> Void
    public let onTap: () -> Void

    @State private var pulse: Bool = false
    @GestureState private var isPressed: Bool = false

    public init(
        phase: Phase,
        onPressBegan: @escaping () -> Void,
        onPressEnded: @escaping () -> Void,
        onTap: @escaping () -> Void
    ) {
        self.phase = phase
        self.onPressBegan = onPressBegan
        self.onPressEnded = onPressEnded
        self.onTap = onTap
    }

    public var body: some View {
        ZStack {
            // outer pulse rings
            if isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.35), lineWidth: 2)
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulse ? 1.3 : 0.95)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
            }

            // main button
            Circle()
                .fill(buttonColor)
                .frame(width: 78, height: 78)
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)

            Image(systemName: iconName)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
        }
        .contentShape(Circle())
        .gesture(
            LongPressGesture(minimumDuration: 0.15)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .updating($isPressed) { value, state, _ in
                    switch value {
                    case .first, .second: state = true
                    default: state = false
                    }
                }
                .onChanged { value in
                    switch value {
                    case .first:
                        if !pulseStarted { onPressBegan(); pulseStarted = true }
                    case .second(true, _):
                        // still pressed
                        break
                    default:
                        if pulseStarted { onPressEnded(); pulseStarted = false }
                    }
                }
                .onEnded { _ in
                    if pulseStarted { onPressEnded(); pulseStarted = false }
                }
        )
        .onTapGesture { onTap() }
        .onAppear { pulse = isRecording }
        .onChange(of: isRecording) { _, newValue in
            pulse = newValue
        }
        .accessibilityLabel(Text("Push to talk"))
    }

    private var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    @State private var pulseStarted: Bool = false

    private var buttonColor: Color {
        switch phase {
        case .idle:        return Color(white: 0.22)
        case .recording:   return .red
        case .processing:  return Color(white: 0.32)
        case .error:       return Color(white: 0.22)
        }
    }

    private var iconName: String {
        switch phase {
        case .idle:        return "mic.fill"
        case .recording:   return "stop.fill"
        case .processing:  return "ellipsis"
        case .error:       return "exclamationmark.triangle.fill"
        }
    }
}
