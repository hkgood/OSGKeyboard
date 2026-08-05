// NativeKeyboardKeyStyle.swift
// OSGKeyboard · Keyboard Extension
//
// Shared native-like key surface used by voice and typing action rows.

import SwiftUI

enum NativeKeyboardKeyColors {
    static func fill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.32) : .white
    }

    static func pressedFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(white: 0.23) : Color(white: 0.84)
    }

    static func text(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : Color(red: 0.06, green: 0.06, blue: 0.08)
    }

    /// Adaptive brand green: brighter in dark mode and deeper in light mode.
    static func sendFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.286, green: 0.725, blue: 0.416)
            : Color(red: 0.196, green: 0.549, blue: 0.298)
    }

    static func sendPressedFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? Color(red: 0.227, green: 0.627, blue: 0.353)
            : Color(red: 0.157, green: 0.447, blue: 0.247)
    }
}

struct NativeKeyboardKeySurface<Content: View>: View {
    let isPressed: Bool
    let fill: Color
    let pressedFill: Color
    let border: Color
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPressed ? pressedFill : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 0.5)
            )
            .shadow(
                color: Color.black.opacity(isPressed ? 0.04 : 0.13),
                radius: isPressed ? 0.5 : 1,
                y: isPressed ? 0 : 1
            )
            .scaleEffect(isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}

struct NativeKeyboardKeyStyle: ButtonStyle {
    let fill: Color
    let pressedFill: Color
    let border: Color
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        NativeKeyboardKeySurface(
            isPressed: configuration.isPressed,
            fill: fill,
            pressedFill: pressedFill,
            border: border,
            cornerRadius: cornerRadius
        ) {
            configuration.label
        }
    }
}
