// Theme.swift
// OSGKeyboard · Main App
//
// Centralised colours, fonts, and reusable modifiers so the app looks
// coherent. Inspired by Typeless: dark base, soft frosted surfaces,
// generous whitespace, large rounded buttons.

import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let card = Color(white: 0.12)
    static let accent = Color(red: 0.36, green: 0.78, blue: 0.98)   // soft cyan
    static let danger = Color(red: 0.97, green: 0.42, blue: 0.45)
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.7)
    static let divider = Color(white: 0.18)
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 0.5)
            )
    }
}
