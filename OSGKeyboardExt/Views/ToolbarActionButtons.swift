// ToolbarActionButtons.swift
// OSGKeyboard · Keyboard Extension
//
// Bottom-row action keys: repeating delete, space, and return.

import SwiftUI
import OSGKeyboardShared

// MARK: - Layout metrics

private enum ToolbarButtonMetrics {
    static let iconSize: CGFloat = 14
    static let titleSize: CGFloat = 16
    static let cornerRadius: CGFloat = KeyboardChromeLayout.actionKeyCornerRadius
    static let spaceBarCapsuleWidth: CGFloat = 31
}

private enum ToolbarKeyEmphasis {
    case standard
    case send
}

// MARK: - Press styling

private struct ToolbarKeySurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette

    let isPressed: Bool
    let cornerRadius: CGFloat
    let emphasis: ToolbarKeyEmphasis
    @ViewBuilder let content: () -> Content

    var body: some View {
        NativeKeyboardKeySurface(
            isPressed: isPressed,
            fill: buttonFill,
            pressedFill: buttonPressedFill,
            border: buttonBorder,
            cornerRadius: cornerRadius,
            content: content
        )
    }

    private var buttonFill: Color {
        switch emphasis {
        case .standard:
            return NativeKeyboardKeyColors.fill(for: colorScheme)
        case .send:
            return NativeKeyboardKeyColors.sendFill(for: colorScheme)
        }
    }

    private var buttonPressedFill: Color {
        switch emphasis {
        case .standard:
            return NativeKeyboardKeyColors.pressedFill(for: colorScheme)
        case .send:
            return NativeKeyboardKeyColors.sendPressedFill(for: colorScheme)
        }
    }

    private var buttonBorder: Color {
        switch emphasis {
        case .standard:
            return palette.divider
        case .send:
            return Color.black.opacity(colorScheme == .dark ? 0.10 : 0.08)
        }
    }
}

// MARK: - Repeating delete

/// Shared hold-to-repeat timing for delete keys (voice + typing).
enum RepeatingDeleteTiming {
    static let initialDelay: TimeInterval = 0.4
    static let normalInterval: TimeInterval = 0.08
    static let accelTier2: TimeInterval = 0.05
    static let accelTier3: TimeInterval = 0.03
    static let accelTier4: TimeInterval = 0.015

    static func interval(for elapsed: TimeInterval) -> TimeInterval {
        if elapsed < 5 { return normalInterval }
        if elapsed < 8 { return accelTier2 }
        if elapsed < 12 { return accelTier3 }
        return accelTier4
    }
}

/// Tap fires once; hold repeats with tiered acceleration after 5 s.
/// Voice and typing delete keys share this press engine.
struct RepeatingPressButton<Label: View>: View {
    var disabled: Bool = false
    /// Plays the system delete click on each fire (matches stock keyboard).
    var playsDeleteSound: Bool = true
    /// Settings → General → Haptics; `.off` skips impact feedback.
    var hapticIntensity: KeyboardHapticIntensity = .off
    let action: () -> Void
    @ViewBuilder let label: (_ isPressed: Bool) -> Label

    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var repeatStartedAt: Date?

    var body: some View {
        label(isPressing)
            .contentShape(Rectangle())
            .gesture(pressGesture)
            .opacity(disabled ? 0.38 : 1)
            .allowsHitTesting(!disabled)
            .accessibilityLabel(Text("delete"))
            .accessibilityAddTraits(.isButton)
            .onDisappear { stopRepeating() }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !disabled, !isPressing else { return }
                isPressing = true
                repeatStartedAt = Date()
                fireOnce()
                startRepeating()
            }
            .onEnded { _ in
                stopRepeating()
            }
    }

    private func fireOnce() {
        if playsDeleteSound {
            KeyboardSoundFeedback.deleteClick()
        }
        KeyboardHapticFeedback.play(role: .delete, intensity: hapticIntensity)
        action()
    }

    private func startRepeating() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: UInt64(RepeatingDeleteTiming.initialDelay * 1_000_000_000)
            )
            guard !Task.isCancelled, isPressing else { return }
            let anchor = repeatStartedAt ?? Date()
            while !Task.isCancelled, isPressing {
                fireOnce()
                let elapsed = Date().timeIntervalSince(anchor)
                let wait = RepeatingDeleteTiming.interval(for: elapsed)
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    private func stopRepeating() {
        isPressing = false
        repeatStartedAt = nil
        repeatTask?.cancel()
        repeatTask = nil
    }
}

/// Voice-toolbar delete chrome around ``RepeatingPressButton``.
struct RepeatingDeleteButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let disabled: Bool
    /// Mirrors Settings → General → Haptics (same as typing delete).
    var hapticIntensity: KeyboardHapticIntensity = .off
    let action: () -> Void

    var body: some View {
        RepeatingPressButton(
            disabled: disabled,
            hapticIntensity: hapticIntensity,
            action: action
        ) { isPressed in
            ToolbarKeySurface(
                isPressed: isPressed,
                cornerRadius: ToolbarButtonMetrics.cornerRadius,
                emphasis: .standard
            ) {
                Image(systemName: "delete.left")
                    .font(.system(size: ToolbarButtonMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(NativeKeyboardKeyColors.text(for: colorScheme))
            }
        }
    }
}

// MARK: - Rectangular toolbar button

struct RectangularToolbarButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let systemName: String?
    let spaceStyle: Bool
    let title: String?
    let label: String
    let disabled: Bool
    let isSend: Bool
    let usesLiquidGlass: Bool
    /// Settings → General → Haptics; space / return use `.action` role.
    var hapticIntensity: KeyboardHapticIntensity = .off
    let action: () -> Void

    init(
        systemName: String,
        label: String,
        disabled: Bool = false,
        usesLiquidGlass: Bool = false,
        hapticIntensity: KeyboardHapticIntensity = .off,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.spaceStyle = false
        self.title = nil
        self.label = label
        self.disabled = disabled
        self.isSend = false
        self.usesLiquidGlass = usesLiquidGlass
        self.hapticIntensity = hapticIntensity
        self.action = action
    }

    init(
        title: String,
        label: String,
        disabled: Bool = false,
        isSend: Bool = false,
        usesLiquidGlass: Bool = false,
        hapticIntensity: KeyboardHapticIntensity = .off,
        action: @escaping () -> Void
    ) {
        self.systemName = nil
        self.spaceStyle = false
        self.label = label
        self.disabled = disabled
        self.isSend = isSend
        self.usesLiquidGlass = usesLiquidGlass
        self.hapticIntensity = hapticIntensity
        self.action = action
        self.title = title
    }

    init(
        spaceStyle: Bool,
        label: String,
        disabled: Bool = false,
        usesLiquidGlass: Bool = false,
        hapticIntensity: KeyboardHapticIntensity = .off,
        action: @escaping () -> Void
    ) {
        self.systemName = nil
        self.spaceStyle = spaceStyle
        self.title = nil
        self.label = label
        self.disabled = disabled
        self.isSend = false
        self.usesLiquidGlass = usesLiquidGlass
        self.hapticIntensity = hapticIntensity
        self.action = action
    }

    @State private var isPressing = false

    var body: some View {
        buttonSurface
            .contentShape(Rectangle())
            .gesture(pressGesture)
            .opacity(disabled ? 0.38 : 1)
            .allowsHitTesting(!disabled)
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var buttonSurface: some View {
        if usesLiquidGlass {
            ZStack {
                Color.clear
                buttonContent
            }
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(
                    cornerRadius: ToolbarButtonMetrics.cornerRadius,
                    style: .continuous
                )
            )
            // The custom press gesture fires on touch-down; mirror that state
            // visually while Liquid Glass supplies its native light response.
            .scaleEffect(isPressing ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressing)
        } else {
            ToolbarKeySurface(
                isPressed: isPressing,
                cornerRadius: ToolbarButtonMetrics.cornerRadius,
                emphasis: isSend ? .send : .standard
            ) {
                buttonContent
            }
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        if spaceStyle {
            Capsule()
                .fill(buttonForeground)
                .frame(width: ToolbarButtonMetrics.spaceBarCapsuleWidth, height: 3)
        } else if let systemName {
            Image(systemName: systemName)
                .font(.system(size: ToolbarButtonMetrics.iconSize, weight: .semibold))
                .foregroundStyle(buttonForeground)
        } else if let title {
            Text(title)
                .font(.system(size: ToolbarButtonMetrics.titleSize, weight: .semibold))
                .foregroundStyle(buttonForeground)
        }
    }

    private var buttonForeground: Color {
        isSend ? .white : NativeKeyboardKeyColors.text(for: colorScheme)
    }

    // 按下即响、即震、即执行，与系统键盘 / 打字面保持一致（Button 默认松手才触发）。
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !disabled, !isPressing else { return }
                isPressing = true
                KeyboardSoundFeedback.keyClick()
                KeyboardHapticFeedback.play(role: .action, intensity: hapticIntensity)
                action()
            }
            .onEnded { _ in
                isPressing = false
            }
    }
}
