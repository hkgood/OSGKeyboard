// ToolbarActionButtons.swift
// OSGKeyboard · Keyboard Extension
//
// Bottom-row action keys: repeating delete, space, and return.

import SwiftUI
import UIKit
import OSGKeyboardShared

// MARK: - Layout metrics

private enum ToolbarButtonMetrics {
    static let iconSize: CGFloat = 14
    static let cornerRadius: CGFloat = 12
    static let spaceBarCapsuleWidth: CGFloat = 31
    static let pressScale: CGFloat = 0.94
    static let pressOverlayOpacity: CGFloat = 0.18
}

// MARK: - Haptics

private enum ToolbarHaptics {
    @MainActor
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Press styling

private struct ToolbarKeyPressStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(ToolbarButtonMetrics.pressOverlayOpacity))
                }
            }
            .scaleEffect(configuration.isPressed ? ToolbarButtonMetrics.pressScale : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}

private struct ToolbarKeySurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette

    let isPressed: Bool
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(buttonFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(palette.dividerStrong, lineWidth: 0.5)
            }
            .overlay {
                if isPressed {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(ToolbarButtonMetrics.pressOverlayOpacity))
                }
            }
            .scaleEffect(isPressed ? ToolbarButtonMetrics.pressScale : 1)
            .animation(.easeOut(duration: 0.1), value: isPressed)
    }

    private var buttonFill: Color {
        let base = colorScheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.22)
            : palette.surfaceElevated
        return isPressed ? base.opacity(0.82) : base
    }
}

// MARK: - Repeating delete

/// Tap deletes once; hold repeats with tiered acceleration after 5 s.
struct RepeatingDeleteButton: View {
    @Environment(\.themePalette) private var palette

    let disabled: Bool
    let action: () -> Void

    @State private var isPressing = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var repeatStartedAt: Date?

    private let initialDelay: TimeInterval = 0.4
    private let normalInterval: TimeInterval = 0.08
    private let accelTier2: TimeInterval = 0.05
    private let accelTier3: TimeInterval = 0.03
    private let accelTier4: TimeInterval = 0.015

    var body: some View {
        ToolbarKeySurface(isPressed: isPressing, cornerRadius: ToolbarButtonMetrics.cornerRadius) {
            Image(systemName: "delete.left")
                .font(.system(size: ToolbarButtonMetrics.iconSize, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .opacity(disabled ? 0.38 : 1)
        .allowsHitTesting(!disabled)
        .accessibilityLabel(Text("delete"))
        .accessibilityAddTraits(.isButton)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !disabled, !isPressing else { return }
                isPressing = true
                repeatStartedAt = Date()
                ToolbarHaptics.tap()
                action()
                startRepeating()
            }
            .onEnded { _ in
                stopRepeating()
            }
    }

    private func interval(for elapsed: TimeInterval) -> TimeInterval {
        if elapsed < 5 { return normalInterval }
        if elapsed < 8 { return accelTier2 }
        if elapsed < 12 { return accelTier3 }
        return accelTier4
    }

    private func startRepeating() {
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            guard !Task.isCancelled, isPressing else { return }
            let anchor = repeatStartedAt ?? Date()
            while !Task.isCancelled, isPressing {
                action()
                let elapsed = Date().timeIntervalSince(anchor)
                let wait = interval(for: elapsed)
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

// MARK: - Rectangular toolbar button

struct RectangularToolbarButton: View {
    @Environment(\.themePalette) private var palette

    let systemName: String?
    let spaceStyle: Bool
    let label: String
    let disabled: Bool
    let action: () -> Void

    init(systemName: String, label: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.systemName = systemName
        self.spaceStyle = false
        self.label = label
        self.disabled = disabled
        self.action = action
    }

    init(spaceStyle: Bool, label: String, disabled: Bool = false, action: @escaping () -> Void) {
        self.systemName = nil
        self.spaceStyle = spaceStyle
        self.label = label
        self.disabled = disabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if spaceStyle {
                    Capsule()
                        .fill(palette.textPrimary)
                        .frame(width: ToolbarButtonMetrics.spaceBarCapsuleWidth, height: 3)
                } else if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: ToolbarButtonMetrics.iconSize, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(keyBackground)
            .overlay(
                RoundedRectangle(cornerRadius: ToolbarButtonMetrics.cornerRadius, style: .continuous)
                    .stroke(palette.dividerStrong, lineWidth: 0.5)
            )
        }
        .buttonStyle(ToolbarKeyPressStyle(cornerRadius: ToolbarButtonMetrics.cornerRadius))
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1)
        .accessibilityLabel(Text(label))
    }

    @Environment(\.colorScheme) private var colorScheme

    private var keyBackground: some View {
        let fill = colorScheme == .dark
            ? Color(red: 0.20, green: 0.20, blue: 0.22)
            : palette.surfaceElevated
        return RoundedRectangle(cornerRadius: ToolbarButtonMetrics.cornerRadius, style: .continuous)
            .fill(fill)
    }
}
