// NativeKeyboardKeyStyle.swift
// OSGKeyboard · Keyboard Extension
//
// Shared native-like key surface used by voice and typing action rows.

import OSGKeyboardShared
import SwiftUI

enum NativeKeyboardKeyColors {
    static func fill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? OSGColor.keyboardDarkKeyFill
            : OSGColor.fixedLightContent
    }

    static func pressedFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? OSGColor.keyboardDarkKeyPressed
            : OSGColor.keyboardLightKeyPressed
    }

    static func text(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? OSGColor.fixedLightContent : OSGColor.keyboardLightText
    }

    /// Adaptive brand green: brighter in dark mode and deeper in light mode.
    static func sendFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? OSGColor.keyboardDarkSend
            : OSGColor.keyboardLightSend
    }

    static func sendPressedFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark
            ? OSGColor.keyboardDarkSendPressed
            : OSGColor.keyboardLightSendPressed
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
            // 无投影：键面层次交给填充 + 0.5pt 描边，避免外扩阴影被键盘边界裁切。
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 0.5)
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
