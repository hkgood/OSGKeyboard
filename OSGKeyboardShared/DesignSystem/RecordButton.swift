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
        /// Clipboard intent is acquiring material or warming the host; tap cancels.
        case preparing
        case recording
        case processing
        case error
    }

    public let phase: Phase
    public let level: Double
    public let remainingSeconds: Int?
    public let isEnabled: Bool
    /// When true (and `phase == .recording`), use blue clipboard-command chrome.
    public let isClipboardCommandRecording: Bool
    public let onToggle: () -> Void
    /// When non-nil, a 0.45s hold starts clipboard-command recording (tap again to stop).
    public let onClipboardLongPressBegan: (() -> Void)?

    @State private var breath = false
    /// Set once a press has been consumed as a hold, so its release is not
    /// replayed as a tap. Must survive phase changes: the phase flips to
    /// `.preparing` / `.recording` while the initiating finger is still down.
    @State private var longPressArmed = false

    public init(
        phase: Phase,
        level: Double,
        remainingSeconds: Int? = nil,
        isEnabled: Bool = true,
        isClipboardCommandRecording: Bool = false,
        onToggle: @escaping () -> Void,
        onClipboardLongPressBegan: (() -> Void)? = nil
    ) {
        self.phase = phase
        self.level = level
        self.remainingSeconds = remainingSeconds
        self.isEnabled = isEnabled
        self.isClipboardCommandRecording = isClipboardCommandRecording
        self.onToggle = onToggle
        self.onClipboardLongPressBegan = onClipboardLongPressBegan
    }

    private var isUrgent: Bool {
        guard phase == .recording, let remainingSeconds else { return false }
        return remainingSeconds <= 10
    }

    /// Active recording tint: blue for clipboard-command, red for dictation.
    private var recordingTint: Color {
        isClipboardCommandRecording ? palette.recordBlue : palette.recordRed
    }

    private var waveformColor: Color {
        isClipboardCommandRecording
            ? Color(red: 0.78, green: 0.88, blue: 1.0)
            : Color(red: 1.0, green: 0.78, blue: 0.78)
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
                .stroke(recordingTint.opacity(isUrgent ? 0.55 : 0.35), lineWidth: isUrgent ? 3 : 2)
                .frame(width: Layout.breathRing, height: Layout.breathRing)
                .scaleEffect(breath ? 1.18 : 0.95)
                .opacity(phase == .recording ? 1 : 0)
                .animation(Motion.breath, value: breath)
                .animation(colorTransition, value: isClipboardCommandRecording)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [recordingTint.opacity(0.55), .clear],
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
                .animation(colorTransition, value: isClipboardCommandRecording)

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
                                color: waveformColor,
                                active: true
                            )
                            .frame(width: 73, height: 32)
                            .opacity(0.4)
                            .scaleEffect(0.96)
                        }
                        .transition(.opacity)
                    case .preparing, .processing:
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
            .animation(colorTransition, value: isClipboardCommandRecording)
        }
        .contentShape(Circle())
        .modifier(
            RecordButtonPressModifier(
                phase: phase,
                isEnabled: isEnabled,
                supportsClipboardLongPress: onClipboardLongPressBegan != nil,
                longPressArmed: $longPressArmed,
                onToggle: onToggle,
                onClipboardLongPressBegan: onClipboardLongPressBegan
            )
        )
        .onAppear { breath = (phase == .recording) }
        .onChange(of: phase) { _, new in
            breath = (new == .recording)
        }
        .accessibilityLabel(Text(SharedL10n.string("keyboard.tapToTalkA11y")))
    }

    /// Red ↔ blue mode switch (~0.25s).
    private var colorTransition: Animation {
        .easeInOut(duration: 0.25)
    }

    private var isIdle: Bool {
        switch phase {
        case .idleReady, .idleUnavailable:
            return true
        case .preparing, .recording, .processing, .error:
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
                ? [recordingTint, recordingTint.opacity(0.85)]
                : [recordingTint.opacity(0.95), recordingTint.opacity(0.75)]
            return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
        case .preparing, .processing:
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

// MARK: - Press / long-press routing

private struct RecordButtonPressModifier: ViewModifier {
    let phase: RecordButton.Phase
    let isEnabled: Bool
    let supportsClipboardLongPress: Bool
    @Binding var longPressArmed: Bool
    let onToggle: () -> Void
    let onClipboardLongPressBegan: (() -> Void)?

    /// A single recognizer serves every phase. Branching on `phase` here would
    /// rebuild the gesture mid-press — clipboard long-press flips the phase while
    /// the finger is still down — and SwiftUI hands that in-flight touch to the
    /// fresh recognizer, letting one press both open and close a round.
    func body(content: Content) -> some View {
        content.onLongPressGesture(
            minimumDuration: ClipboardMaterialFilter.longPressDuration,
            maximumDistance: 120,
            pressing: { pressing in
                if pressing {
                    longPressArmed = false
                    return
                }
                // A press already consumed as a hold must not replay as a tap.
                if longPressArmed {
                    longPressArmed = false
                    return
                }
                handleTap()
            },
            perform: { longPressArmed = handleHold() }
        )
    }

    private func handleTap() {
        dispatch(RecordButtonGesturePolicy.tapAction(phase: phase, isEnabled: isEnabled))
    }

    /// Returns whether the hold consumed the press.
    private func handleHold() -> Bool {
        let action = RecordButtonGesturePolicy.holdAction(
            phase: phase,
            isEnabled: isEnabled,
            supportsClipboardLongPress: supportsClipboardLongPress
        )
        dispatch(action)
        return RecordButtonGesturePolicy.consumesPress(action)
    }

    private func dispatch(_ action: RecordButtonGestureAction) {
        switch action {
        case .none:
            break
        case .toggle:
            onToggle()
        case .beginClipboardCommand:
            onClipboardLongPressBegan?()
        }
    }
}
